require 'http'

class WebhookWorker
  include Sidekiq::Worker

  def perform(webhook_event_id)
    webhook_event = WebhookEvent.find_by(id: webhook_event_id)
    return if
      webhook_event.nil?

    webhook_endpoint = webhook_event.webhook_endpoint
    return if
      webhook_endpoint.nil?

    # Send the webhook request with a 30 second timeout.
    response = HTTP.timeout(30)
                   .headers(
                     'User-Agent' => 'rails_webhook_system/1.0',
                     'Content-Type' => 'application/json'
                   )
                   .post(
                     webhook_endpoint.url,
                     body: {
                       event: webhook_event.event,
                       payload: webhook_event.payload
                     }.to_json
                   )

    # Store the webhook response.
    webhook_event.update(response: {
                           headers: response.headers.to_h,
                           code: response.code.to_i,
                           body: response.body.to_s
                         })

    # Raise a failed request error and let Sidekiq handle retrying.
    raise FailedRequestError unless
      response.status.success?
  rescue HTTP::TimeoutError
    # This error means the webhook endpoint timed out. We can either
    # raise a failed request error to trigger a retry, or leave it
    # as-is and consider timeouts terminal. We'll do the latter.
    webhook_event.update(response: { error: 'TIMEOUT_ERROR' })
  end

  # General failed request error that we're going to use to signal
  # Sidekiq to retry our webhook worker.
  class FailedRequestError < StandardError; end
end
