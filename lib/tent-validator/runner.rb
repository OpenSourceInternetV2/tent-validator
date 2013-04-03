require 'tent-validator/mixins/deep_merge'

module TentValidator
  module Runner

    class Results
      include Mixins::DeepMerge

      attr_reader :results
      def initialize
        @results = {}
      end

      def merge!(validator_results)
        deep_merge!(results, validator_results.results)
      end

      def as_json(options = {})
        results
      end
    end

    require 'tent-validator/runner/cli'

    def self.run(&block)
      paths = Dir[File.expand_path(File.join(File.dirname(__FILE__), 'validators', '**', '*_validator.rb'))]
      paths.each { |path| require path }

      results = Results.new

      TentValidator.validators.each do |validator|
        results.merge!(validator.run)
        block.call(results) if block
      end

      results
    end

  end
end
