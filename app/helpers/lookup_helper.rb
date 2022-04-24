# frozen_string_literal: true

#noinspection RubyClassVariableUsageInspection
class VerifierKeys
  @@verifier_keys = nil

  def self.verifier_keys
    return @@verifier_keys unless @@verifier_keys.nil?
    begin
      @@verifier_keys = JSON.parse File.read(ENV['VERIFIERS_FILE'])
    rescue => e
      Rails.logger.error e
      @@verifier_keys = {}
    end
    @@verifier_keys.each do |uri, key|
      next unless key.nil?
      begin
        actor = Class.new.extend(JsonLdHelper).fetch_resource_without_id_validation(uri)
        @@verifier_keys[uri] = actor['publicKey']['publicKeyPem']
      rescue => e
        Rails.logger.error e
      end
    end
    File.open(ENV['VERIFIERS_FILE'], 'w') do |f|
      f.write(JSON.pretty_generate(@@verifier_keys))
    end
    @@verifier_keys.each do |uri, key|
      @@verifier_keys[uri] = OpenSSL::PKey::RSA.new key unless key.nil?
    end
    @@verifier_keys
  end
end

module LookupHelper
  def extract_lookup_data(data)
    return if data.nil?

    signatures = data['key_signatures']
    return if signatures.nil? || !signatures.is_a?(Array)

    json = data['json']
    aux = data['aux']
    json = JSON.parse json
    aux = JSON.parse aux || {}
    return if json.nil?

    verified = signatures_valid(json, aux, signatures)
    return nil if verified.include? false
    return [json, aux] if verified.count(true) >= 1
    nil
  end

  private

  def signatures_valid(json, aux, signatures)
    verifier_keys = VerifierKeys.verifier_keys

    signatures.map do |v|
      signed_by = v['signed_by']
      signature = Base64.decode64(v['signature'])
      signature_time = v['signature_time']
      signed_string = create_signed_string(json, aux, signature_time)
      next nil if verifier_keys[signed_by].nil?
      correct_signature?(verifier_keys[signed_by], signature, signed_string)
    end
  end

  def correct_signature?(public_key, signature, signed_string)
    public_key.verify(OpenSSL::Digest.new('SHA256'), signature, signed_string)
  rescue OpenSSL::PKey::RSAError
    false
  end

  def sort_hashes(json)
    if json.is_a?(Hash)
      Hash[json.sort.map { |e| [e[0], (sort_hashes e[1])] }]
    elsif json.is_a?(Array)
      json.map {|e| (sort_hashes e)}
    else
      json
    end
  end

  def create_signed_string(json, aux, sign_time)
    to_sign = {
      "actor_id" => json['id'],
      "actor_uri" => json['uri'],
      "actor_type" => json['type'],
      "actor_following" => json['following'],
      "actor_followers" => json['followers'],
      "actor_inbox" => json['inbox'],
      "actor_outbox" => json['outbox'],
      "actor_name" => json['name'],
      "actor_url" => json['url'],
      "actor_published" => json['published'],
      "actor_endpoints" => json['endpoints'],
      "webfinger" => aux['webfinger'],
      "key" => json['publicKey'] || {},
      "signature_time" => sign_time,
    }
    JSON.generate(sort_hashes to_sign)
  end
end
