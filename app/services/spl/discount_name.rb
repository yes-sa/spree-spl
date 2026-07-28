# frozen_string_literal: true

module Spl
  # SPL discount names include a trade-agreement prefix, e.g. "123L.Dla Patryka".
  # Customers should only see the part after the first dot.
  module DiscountName
    module_function

    def customer_label(name, trade_agreement_number: nil)
      return if name.blank?

      name = name.to_s
      if trade_agreement_number.present?
        ["#{trade_agreement_number}. ", "#{trade_agreement_number}."].each do |prefix|
          next unless name.start_with?(prefix)

          return name.delete_prefix(prefix).strip.presence || name.strip
        end
      end

      name.split('.', 2).last.to_s.strip.presence || name.strip
    end
  end
end
