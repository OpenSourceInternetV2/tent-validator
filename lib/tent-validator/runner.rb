require 'api-validator'
require 'awesome_print'
require 'benchmark'

module TentValidator
  module Runner

    class Results
      include ApiValidator::Mixins::DeepMerge

      attr_reader :results, :num_skipped
      def initialize
        @results = {}
        @num_skipped = 0
      end

      def merge!(validator_results)
        deep_merge!(results, validator_results.results)
      end

      def skipped(validator)
        if validator.respond_to?(:expectations)
          @num_skipped += validator.expectations.size
        end
        validator.validations.each { |v| skipped(v) }
      end

      def as_json(options = {})
        results
      end
    end

    require 'tent-validator/runner/cli'

    def self.run(&block)
      TentValidator.run_local_server!

      print "Loading validations..."
      load_time = Benchmark.realtime do
        paths = Dir[File.expand_path(File.join(File.dirname(__FILE__), 'validators', '**', '*_validator.rb'))]
        paths.each { |path| require path }
      end
      print " #{load_time}s\n"

      results = Results.new

      TentValidator.validators.each do |validator|
        begin
          results.merge!(validator.run)
          block.call(results) if block
        rescue SetupFailure => e
          if e.results
            _setup_failure_results = ApiValidator::ResponseExpectation::Results.new(e.response, [e.results])
            results.merge!(ApiValidator::Spec::Results.new(validator, [_setup_failure_results]))
            results.skipped(validator)
          else
            puts %(<#{validator.name} SetupFailure "#{e.message}">:)

            if e.response
              print "\tRESPONSE:\n\t"
              print "status: #{e.response.status}\n\t"
              begin
                print Yajl::Encoder.encode(e.response.body)
              rescue
                print e.response.body
              end
              print "\n\n"
            end

            puts "\t" + e.backtrace.join("\n\t")
          end
        end
      end

      TentValidator.mutex.synchronize do
        if TentValidator.async_local_request_expectations.empty?
          return results
        else
          timeout = Time.now.to_i + 10
          expectations = []
          ticks = 0
          until TentValidator.async_local_request_expectations.empty?
            TentValidator.local_requests.each do |req|
              _env, _res = req
              _req_path, _req_method = _env['PATH_INFO'], _env['REQUEST_METHOD']
              if (_expectations = TentValidator.async_local_request_expectations.select { |expectation|
                expectation.path_expectations.any? { |e| e.send(:failed_assertions, _req_path).empty? } &&
                expectation.method_expectations.any? { |e| e.send(:failed_assertions, _req_method).empty? }
              }) && _expectations.any?
                if _expectations.size == 1
                  _expectation = _expectations.first
                else
                  _expectation = _expectations.find { |expectation|
                    expectation.validate(expectation.build_request(_env)).any? { |r|
                      r[:valid]
                    }
                  } || _expectations.first
                end

                TentValidator.async_local_request_expectations.delete(_expectation)
                expectations << [req, _expectation]
              end
            end

            break if Time.now.to_i >= timeout
            if TentValidator.async_local_request_expectations.any?
              if ticks == 0
                print "\n"
                print "Wating for incoming requests... "
              end
              print "#{timeout - Time.now.to_i}."
              ticks += 1
              sleep(1)
            end
          end

          # Requests found for these expectations
          expectations.each do |i|
            _req, expectation = i
            _env, _res = _req

            results.merge!(ApiValidator::Spec::Results.new(expectation.validator, [expectation.run(_env, _res)]))
          end

          # No requests found for these expectations
          TentValidator.async_local_request_expectations.each do |expectation|
            results.merge!(ApiValidator::Spec::Results.new(expectation.validator, [expectation.run({}, [])]))
          end

          # Reset
          TentValidator.async_local_request_expectations.delete_if { true }

          block.call(results)

          results
        end
      end
    end

  end
end
