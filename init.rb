require 'redmine'

Rails.configuration.to_prepare do
    require_dependency 'that_meeting_hook'
end

Rails.logger.info 'Starting That Meeting plugin for Redmine'

IssueQuery.add_available_column(QueryColumn.new(:formatted_start_time, :caption => :field_start_time))
IssueQuery.add_available_column(QueryColumn.new(:formatted_end_time, :caption => :field_end_time))
IssueQuery.add_available_column(QueryColumn.new(:recurrence))


Redmine::Plugin.register :that_meeting do
    name 'That Meeting'
    author 'Andriy Lesyuk for That Company'
    author_url 'http://www.andriylesyuk.com/'
    description 'Converts issues of the selected trackers into iCalendar events.'
    url 'https://github.com/thatcompany/that_meeting'
    version '1.0.0'

    settings :default => {
        'tracker_ids' => [],
        'hide_mails' => true,
        'cancel_status_ids' => [],
        'force_notifications' => false,
        'no_reply_notify' => false,
        'system_timezone' => (File.read('/etc/timezone').strip rescue nil),
        'timezone_format' => '%Z'
    }, :partial => 'settings/meeting'
end
