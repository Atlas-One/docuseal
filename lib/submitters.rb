# frozen_string_literal: true

module Submitters
  TRUE_VALUES = ['1', 'true', true].freeze

  module_function

  def search(submitters, keyword)
    return submitters if keyword.blank?

    term = "%#{keyword.downcase}%"

    arel_table = Submitter.arel_table

    arel = arel_table[:email].lower.matches(term)
                             .or(arel_table[:phone].matches(term))
                             .or(arel_table[:name].lower.matches(term))

    submitters.where(arel)
  end

  def select_attachments_for_download(submitter)
    original_documents = submitter.submission.template.documents.preload(:blob)
    is_more_than_two_images = original_documents.count(&:image?) > 1

    submitter.documents.preload(:blob).reject do |attachment|
      is_more_than_two_images &&
        original_documents.find { |a| a.uuid == (attachment.metadata['original_uuid'] || attachment.uuid) }&.image?
    end
  end

  def create_attachment!(submitter, params)
    blob =
      if (file = params[:file])
        ActiveStorage::Blob.create_and_upload!(io: file.open,
                                               filename: file.original_filename,
                                               content_type: file.content_type)
      else
        ActiveStorage::Blob.find_signed(params[:blob_signed_id])
      end

    ActiveStorage::Attachment.create!(
      blob:,
      name: params[:name],
      record: submitter
    )
  end

  def normalize_preferences(account, user, params)
    preferences = {}

    message_params = params['message'].presence || params.slice('subject', 'body').presence

    if message_params.present?
      email_message = EmailMessages.find_or_create_for_account_user(account, user,
                                                                    message_params['subject'],
                                                                    message_params['body'])
    end

    preferences['email_message_uuid'] = email_message.uuid if email_message
    preferences['send_email'] = params['send_email'].in?(TRUE_VALUES) if params.key?('send_email')
    preferences['send_sms'] = params['send_sms'].in?(TRUE_VALUES) if params.key?('send_sms')
    preferences['bcc_completed'] = params['bcc_completed'] if params.key?('bcc_completed')
    preferences['completed_redirect_url'] = params['completed_redirect_url'] if params.key?('completed_redirect_url')

    preferences
  end

  def send_signature_requests(submitters)
    submitters.each do |submitter|
      next if submitter.email.blank?
      next if submitter.preferences['send_email'] == false

      SendSubmitterInvitationEmailJob.perform_later('submitter_id' => submitter.id)
    end
  end
end
