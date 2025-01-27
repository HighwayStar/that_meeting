require_dependency 'issues_controller'

module Patches
    module ThatMeetingIssuesControllerPatch

        def self.included(base)
            base.send(:include, InstanceMethods)
            base.class_eval do
                unloadable

                alias_method :show_without_ics, :show
                alias_method :show, :show_with_ics
            end
        end

        module InstanceMethods

            def show_with_ics
                if request.format.ics?
                    if @issue.meeting
                        send_data(@issue.meeting.to_ical(self, User.current, :comments => true).to_ical, :type => 'text/calendar',
                                                                                                         :filename => "#{@project.identifier}-#{@issue.id}.ics")
                    else
                        head 404
                    end
                else
                    show_without_ics
                end
            end

        end

    end
end

unless IssuesController.included_modules.include?(Patches::ThatMeetingIssuesControllerPatch)
    IssuesController.send(:include, Patches::ThatMeetingIssuesControllerPatch)
end