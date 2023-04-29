# frozen_string_literal: true

require 'http'

class WebhookWorker
  include Sidekiq::Worker

  def perform(event)
    @webhook_event    = WebhookEvent.find_by(event: event)
    @webhook_endpoint = @webhook_event&.webhook_endpoint
    return if @webhook_event.blank? || @webhook_endpoint.blank?

    response = handle_request
    @webhook_event.update(response: {
                            headers: response.headers.to_h,
                            code: response.code.to_i,
                            body: response.body.to_s
                          })
  rescue HTTP::TimeoutError
    @webhook_event.update(response: { error: 'TIMEOUT_ERROR' })
  end

  private

  def handle_request
    @handle_request ||= HTTP.timeout(30)
                            .headers(
                              'User-Agent' => 'rails_webhook_system/1.0',
                              'Content-Type' => 'application/json'
                            )
                            .post(
                              @webhook_endpoint.url,
                              body: {
                                event: @webhook_event.event,
                                payload: @webhook_event.payload
                              }.to_json
                            )
  end
end
