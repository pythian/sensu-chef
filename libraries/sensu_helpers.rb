require "openssl"

module Sensu
  class Helpers
    extend ChefVaultItem if Kernel.const_defined?("ChefVaultItem")
    class << self
      def select_attributes(attributes, keys)
        attributes.to_hash.reject do |key, value|
          !Array(keys).include?(key.to_s) || value.nil?
        end
      end

      def sanitize(raw_hash)
        sanitized = Hash.new
        raw_hash.each do |key, value|
          # Expand Chef::DelayedEvaluator (lazy)
          value = value.call if value.respond_to?(:call)

          case value
          when Hash
            sanitized[key] = sanitize(value) unless value.empty?
          when nil
            # noop
          else
            sanitized[key] = value
          end
        end
        sanitized
      end

      def gem_binary
        if File.exists?("/opt/sensu/embedded/bin/gem")
          "/opt/sensu/embedded/bin/gem"
        else
          "gem"
        end
      end

      def data_bag_item(item, missing_ok=false)
        raw_hash = Chef::DataBagItem.load("sensu", item)
        encrypted = raw_hash.detect do |key, value|
          if value.is_a?(Hash)
            value.has_key?("encrypted_data")
          end
        end
        if encrypted
          if Chef::DataBag.load("sensu").key? "#{item}_keys"
            chef_vault_item("sensu", item)
          else
            secret = Chef::EncryptedDataBagItem.load_secret
            Chef::EncryptedDataBagItem.new(raw_hash, secret)
          end
        else
          raw_hash
        end
      rescue Chef::Exceptions::ValidationFailed,
        Chef::Exceptions::InvalidDataBagPath,
        Net::HTTPServerException => error
        missing_ok ? nil : raise(error)
      end

      def random_password(length=20, number=false, upper=false, lower=false, special=false)
        password = ""
        requiredOffset = 0
        requiredOffset += 1 if number
        requiredOffset += 1 if upper
        requiredOffset += 1 if lower
        requiredOffset += 1 if special
        length = requiredOffset if length < requiredOffset
        limit = password.length < (length - requiredOffset)

        while limit || requiredOffset > 0
          push = false
          c = ::OpenSSL::Random.random_bytes(1).gsub(/\W/, '')
          if c != ""
            if c =~ /[[:digit:]]/
              requiredOffset -= 1 if number
              number = false
            elsif c >= 'a' && c <= 'z'
              requiredOffset -= 1 if lower
              lower = false
            elsif c >= 'A' && c <= 'Z'
              requiredOffset -= 1 if upper
              upper = false
            else
              requiredOffset -= 1 if special
              special = false
            end
          end
          limit = password.length < (length - requiredOffset)
          if limit
            password << c
          end
        end
        password
      end
    end
  end
end
