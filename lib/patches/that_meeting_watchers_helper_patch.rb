require_dependency 'watchers_helper'

module Patches
    module ThatMeetingWatchersHelperPatch

        def self.included(base)
            base.prepend(InstanceMethods)
        end

        module InstanceMethods

            def watchers_list(object)
                content = super(object)
                if object.is_a?(Issue) && object.meeting?
                    js = "$('#watchers h3').text('#{j l(:label_attendees)} (#{object.watcher_users.size})');"
                    js << "$('#watchers ul.watchers').addClass('attendees');"
                    object.watcher_users.collect do |user|
                        acceptance = object.meeting.responses_by_user[user.id].try(:downcase)
                        js << "$('#watchers li.user-#{user.id}').append($('<span>', { 'class': 'icon-only meeting-status icon-meeting-#{acceptance || 'needs-action'}', " +
                                                                                      "title: '#{j l("label_meeting_status_#{acceptance || 'none'}")}' }));"
                    end if content.present?
                    content << javascript_tag(js)
                end
                content
            end

        end

    end
end

unless WatchersHelper.included_modules.include?(Patches::ThatMeetingWatchersHelperPatch)
    WatchersHelper.send(:include, Patches::ThatMeetingWatchersHelperPatch)
end