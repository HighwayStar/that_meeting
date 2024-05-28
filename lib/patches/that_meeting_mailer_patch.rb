require_dependency 'mailer'

module Patches
    module ThatMeetingMailerPatch

        def self.included(base)
            if Redmine::VERSION::MAJOR > 3
                base.send(:include, Redmine4InstanceMethods)
            else
                base.send(:include, Redmine3InstanceMethods)
            end
            base.send(:include, InstanceMethods)
            base.class_eval do
                unloadable

                alias_method :issue_add_without_meeting, :issue_add
                alias_method :issue_add, :issue_add_with_meeting

                alias_method :issue_edit_without_meeting, :issue_edit
                alias_method :issue_edit, :issue_edit_with_meeting
            end
        end

        module Redmine4InstanceMethods

            def issue_add_with_meeting(user, issue)
                if issue.meeting? && !issue.meeting.canceled?
                    attach_ical issue, user
                    issue.author.pref.no_self_notified = false if Setting.plugin_that_meeting['force_notifications']
                end
                issue_add_without_meeting(user, issue)
            end

            def issue_edit_with_meeting(user, journal)
                issue = journal.journalized
                if issue.meeting? && meeting_attribute_changed?(journal)
                    attach_ical issue, user
                    journal.user.pref.no_self_notified = false if Setting.plugin_that_meeting['force_notifications']
                end
                issue_edit_without_meeting(user, journal)
            end

        end

        module Redmine3InstanceMethods

            def issue_add_with_meeting(issue, to_users, cc_users)
                if issue.meeting? && !issue.meeting.canceled?
                    all_users = to_users + cc_users
                    attach_ical issue, all_users.size == 1 ? all_users.first : nil
                    issue.author.pref.no_self_notified = false if Setting.plugin_that_meeting['force_notifications']
                end
                issue_add_without_meeting(issue, to_users, cc_users)
            end

            def issue_edit_with_meeting(journal, to_users, cc_users)
                issue = journal.journalized
                if issue.meeting? && meeting_attribute_changed?(journal)
                    all_users = to_users + cc_users
                    attach_ical issue, all_users.size == 1 ? all_users.first : nil
                    journal.user.pref.no_self_notified = false if Setting.plugin_that_meeting['force_notifications']
                end
                issue_edit_without_meeting(journal, to_users, cc_users)
            end

        end

        module InstanceMethods

            def attendee_invited(user, issue, author)
                redmine_headers 'Project' => issue.project.identifier,
                                'Issue-Id' => issue.id,
                                'Issue-Author' => issue.author.login
                redmine_headers 'Issue-Assignee' => issue.assigned_to.login if issue.assigned_to
                message_id issue
                references issue
                attach_ical issue, user
                @author = author
                @issue = issue
                @user = user if Redmine::VERSION::MAJOR > 3
                @users = [ user ] if Redmine::VERSION::MAJOR < 4
                @issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)
                @author.pref.no_self_notified = false if Setting.plugin_that_meeting['force_notifications']
                mail :to => user,
                     :subject => "[#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] (#{issue.status.name}) #{issue.subject}"
            end

            def calendar_counter_declined(address, subject, decline)
                decline.ip_method = 'DECLINECOUNTER'
                attachments['decline.ics'] = {
                    :content => decline.to_ical,
                    :content_type => "text/calendar; method=#{decline.ip_method}"
                }
                mail :to => address, :subject => subject
            end

        private

            def attach_ical(issue, user = nil)
                issue.meeting.exceptions.reload
                meeting = issue.meeting.to_ical(self, user)
                attachments["#{issue.project.identifier}-#{issue.id}.ics"] = {
                    :content => meeting.to_ical,
                    :content_type => "text/calendar; method=#{meeting.ip_method}"
                }
            end

            MEETING_ATTRIBUTES = %w(subject description assigned_to_id priority_id estimated_hours is_private category_id parent_id start_date start_time end_time recurrence).freeze

            def meeting_attribute_changed?(journal)
                journal.details.any? do |detail|
                    if detail.property == 'attr'
                        if detail.prop_key == 'status_id'
                            Setting.plugin_that_meeting['cancel_status_ids'].is_a?(Array) &&
                            Setting.plugin_that_meeting['cancel_status_ids'].include?(detail.old_value.to_s) != Setting.plugin_that_meeting['cancel_status_ids'].include?(detail.value.to_s)
                        else
                            MEETING_ATTRIBUTES.include?(detail.prop_key)
                        end
                    else
                        %w(attachment attendee occurrence).include?(detail.property)
                    end
                end
            end

        end

    end
end


unless Mailer.included_modules.include?(Patches::ThatMeetingMailerPatch)
    Mailer.send(:include, Patches::ThatMeetingMailerPatch)
end