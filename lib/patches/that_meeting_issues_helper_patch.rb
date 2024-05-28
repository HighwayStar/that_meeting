require_dependency 'issues_helper'

module Patches
    module ThatMeetingIssuesHelperPatch

        def self.included(base)
            base.prepend(InstanceMethods)
        end

        module InstanceMethods

            def render_issue_tooltip(issue)
                tooltip = super(issue)
                if issue.meeting?
                    @cached_label_occurrence ||= l(:label_occurrence)
                    @cached_label_date ||= l(:label_date)
                    @cached_label_recurrence ||= l(:field_recurrence)
                    @cached_label_last_date ||= l(:label_last_date)

                    meetinginfo = ''
                    if issue.occurrence
                        meetinginfo << "<strong>#{@cached_label_occurrence}</strong>: #{format_time(issue.occurrence.start_time)}"
                        meetinginfo << " - #{format_time(issue.occurrence.end_time, false)}" if issue.occurrence.end_time
                        meetinginfo << "<br />"
                    end
                    meetinginfo << "<strong>#{@cached_label_date}</strong>: #{format_time(issue.start_time)}"
                    meetinginfo << " - #{format_time(issue.end_time, false)}" if issue.end_time
                    meetinginfo << "<br />"
                    meetinginfo << "<strong>#{@cached_label_recurrence}</strong>: #{issue.recurrence.to_s}<br />"

                    tooltip.sub!(%r{<strong>#{Regexp.escape(@cached_label_start_date)}</strong>: .*?<br />}, meetinginfo)
                    tooltip.sub!(%r{<strong>#{Regexp.escape(@cached_label_due_date)}</strong>:}, "<strong>#{@cached_label_last_date}</strong>:")
                end
                tooltip.html_safe
            end

            def email_issue_attributes(issue, user, html)
                items = super(issue, user, html)
                %w(start_date start_time end_time recurrence).reverse.each do |attribute|
                    if value = issue.send(attribute)
                        case value
                        when Date
                            value = format_date(value)
                        when Time
                            value = format_time_with_timezone(value, false, nil)
                        when IssueMeeting::Recurrence
                            value = value.to_s
                        end
                        next if value.blank?
                        if html
                            items.unshift(content_tag('strong', "#{l("field_#{attribute}")}: ") + value)
                        else
                            items.unshift("#{l("field_#{attribute}")}: #{value}")
                        end
                    end
                end if issue.meeting?
                items
            end

            def show_detail(detail, no_html = false, options = {})
                if detail.property == 'attendee'
                    if detail.value
                        l("label_meeting_status_#{detail.value.downcase}")
                    else
                        l(detail.prop_key.empty? ? :label_meeting_status_all_reset : :label_meeting_status_none)
                    end
                else
                    super(controller.is_a?(Mailer) ? detail.dup : detail, no_html, options)
                end
            end

        end

    end
end

unless IssuesHelper.included_modules.include?(Patches::ThatMeetingIssuesHelperPatch)
    IssuesHelper.send(:include, Patches::ThatMeetingIssuesHelperPatch)
end
