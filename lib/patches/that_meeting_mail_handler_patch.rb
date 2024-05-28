require_dependency 'mail_handler'

module Patches
    module ThatMeetingMailHandlerPatch

        def self.included(base)
            base.send(:include, InstanceMethods)
            base.class_eval do
                unloadable

                alias_method :receive_without_calendar, :receive
                alias_method :receive, :receive_with_calendar

                alias_method :dispatch_to_default_without_calendar, :dispatch_to_default
                alias_method :dispatch_to_default, :dispatch_to_default_with_calendar

                alias_method :receive_issue_reply_without_calendar, :receive_issue_reply
                alias_method :receive_issue_reply, :receive_issue_reply_with_calendar

                alias_method :issue_attributes_from_keywords_without_meeting, :issue_attributes_from_keywords
                alias_method :issue_attributes_from_keywords, :issue_attributes_from_keywords_with_meeting
            end
        end

        module InstanceMethods

            def receive_with_calendar(email, options = {})
                if @calendar_part = email.all_parts.detect{ |part| part.mime_type == 'text/calendar' }
                    # Remove autogeneration headers to let the email pass Redmine's #receive
                    self.class.ignored_emails_headers.keys.each do |header|
                        email.header[header] = nil
                    end
                end
                # Microsoft Outlook 15 sends the response directly in the mail body
                @calendar_part = email if email.all_parts.empty? && email.mime_type == 'text/calendar'
                receive_without_calendar(email, options)
            end

        private

            def dispatch_to_default_with_calendar
                if @calendar_part
                    ical = Icalendar::Calendar.parse(@calendar_part.body.decoded).first
                    case ical.ip_method.try(:upcase)
                    when 'REPLY'
                        return receive_calendar_reply(ical)
                    when 'COUNTER'
                        decline_calendar_counter(ical)
                        return
                    end if ical
                end
                dispatch_to_default_without_calendar
            end

            # This is to support Office 365
            def receive_issue_reply_with_calendar(issue_id, from_journal = nil)
                if @calendar_part
                    ical = Icalendar::Calendar.parse(@calendar_part.body.decoded).first
                    case ical.ip_method.try(:upcase)
                    when 'REPLY'
                        return receive_calendar_reply(ical, cleaned_up_text_body)
                    when 'COUNTER'
                        decline_calendar_counter(ical)
                        return
                    end if ical
                end
                receive_issue_reply_without_calendar(issue_id, from_journal)
            end

            def issue_attributes_from_keywords_with_meeting(issue)
                attributes = issue_attributes_from_keywords_without_meeting(issue)
                if (start_time = get_keyword(:start_time, :format => '\d{1,2}:\d{2}'))
                    attributes['start_time'] = start_time
                end
                if (end_time = get_keyword(:end_time, :format => '\d{1,2}:\d{2}'))
                    attributes['end_time'] = end_time
                end
                attributes
            end

            MEETING_UID_RE = %r{\A[0-9T]+-issue-([0-9]+)@}

            def receive_calendar_reply(ical, notes = nil)
                event = ical.events.first
                unless issue = target_meeting(event)
                    logger.error "MailHandler: Unable to determine target meeting" if logger
                    return true
                end
                unless issue.watched_by?(user) # Is attendee?
                    logger.error "MailHandler: #{user} is not attendee of meeting ##{issue.id}" if logger
                    return true
                end
                user_mails = user.mails.map(&:downcase)
                return true unless attendee = event.attendee.detect{ |attendee| user_mails.include?(attendee.value.to_s.downcase.sub(%r{^mailto:}, '')) }
                return true unless response = attendee.ical_params['partstat']
                response = response.first if response.is_a?(Array)
                response = response.to_s.upcase
                return true unless %w(NEEDS-ACTION ACCEPTED TENTATIVE DECLINED).include?(response)
                response = nil if response == 'NEEDS-ACTION'
                acceptance = issue.acceptances.where(:prop_key => [ user.id, '' ]).first
                if !acceptance || acceptance.value != response
                    notes ||= attendee.ical_params['x-response-comment']
                    notes = notes.first if notes.is_a?(Array)
                    journal = issue.init_journal(user, notes)
                    journal.details << JournalDetail.new(:property => 'attendee', :prop_key => user.id, :value => response)
                    journal.save!
                    logger.info "MailHandler: iCalendar reply received from #{user} for meeting ##{issue.id}" if logger
                    journal
                else
                    true # Otherwise error will be returned
                end
            end

            def decline_calendar_counter(ical)
                event = ical.events.first
                return unless issue = target_meeting(event)
                Mailer.calendar_counter_declined(email.from, "Re: #{email.subject}", ical).deliver
                logger.info "MailHandler: iCalendar counter request from #{user} declined for meeting ##{issue.id}" if logger
            end

            def target_meeting(event)
                if (m = event.uid.match(MEETING_UID_RE)) && (issue = Issue.find_by_id(m[1].to_i)) && issue.meeting?
                    issue
                end
            end

        end

    end
end

unless MailHandler.included_modules.include?(Patches::ThatMeetingMailHandlerPatch)
    MailHandler.send(:include, Patches::ThatMeetingMailHandlerPatch)
end