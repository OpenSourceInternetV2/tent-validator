require 'awesome_print'
require 'benchmark'

module TentValidator
  module Runner

    class CLI

      TRANSLATE_KEYS = {
        :current_value => :actual
      }.freeze

      def self.run(options = {})
        instance = self.new(options)
        instance.run
      end

      def initialize(options = {})
      end

      def run
        @valid = []
        @invalid = []

        puts "Running Protocol Validations..."

        results = nil
        exec_time = Benchmark.realtime do
          results = Runner.run do |results|
            print_results(results.as_json)
          end
        end

        print "\n"
        validator_complete(results.as_json)

        print "\n"
        if @invalid.any?
          print green("#{@valid.uniq.size} validations passed\t") + red("#{@invalid.uniq.size} failed")
        else
          print green("#{@valid.uniq.size} validations passed\t0 failed")
        end
        if results.num_skipped > 0
          print yellow("\t#{results.num_skipped} skipped")
        else
          print green("\t0 skipped")
        end

        print "\t#{exec_time}s"

        print "\n"
        print "\n"

        exit(1) if @invalid.any?
      end

      def print_results(results, parent_names = [])
        results.each_pair do |name, children|
          next if name == :results
          child_results = children[:results]
          child_results.each do |r|
            id = r.object_id.to_s
            valid = result_valid?(r)
            if valid
              next if @valid.index(id)
              @valid << id
              print green(".")
            else
              next if @invalid.index(id)
              if valid == false
                @invalid << id
                print red("F")
              end
            end
          end
          print_results(children, parent_names + [name])
        end
      end

      def validator_complete(results, parent_names = [])
        parent_names.reject! { |n| n == "" }
        results.each_pair do |name, children|
          next if name == :results
          child_results = children[:results]
          child_results.each do |r|
            next if result_valid?(r)

            print "\n"
            puts red((parent_names + [name]).join(" "))
            print "\n"

            actual = r.as_json[:actual]
            puts "REQUEST:"
            puts "#{actual[:request_method]} #{actual[:request_url]}"
            puts (actual[:request_headers] || {}).inject([]) { |m, (k,v)| m << "#{k}: #{v}"; m }.join("\n")
            print "\n"
            puts actual[:request_body]
            print "\n"

            puts "RESPONSE:"
            puts actual[:response_status]
            puts (actual[:response_headers] || {}).inject([]) { |m, (k,v)| m << "#{k}: #{v}"; m }.join("\n")
            print "\n"
            if String === actual[:response_body]
              puts actual[:response_body]
            else
              puts Yajl::Encoder.encode(actual[:response_body])
            end
            print "\n"

            puts "DIFF:"
            r.as_json[:expected].each_pair do |key, val|
              next if val[:valid] || val[:diff].empty?

              puts key
              ap val[:diff].map { |i| translate_keys(i.dup) }
            end
          end
          validator_complete(children, parent_names + [name])
        end
      end

      def result_valid?(result)
        valid = result.as_json[:expected].inject(true) { |memo, (k,v)|
          memo = false if v.has_key?(:valid) && v[:valid] == false
          memo = nil if v.has_key?(:valid) && v[:valid].nil? && memo == true
          memo
        }
      end

      def translate_keys(hash)
        TRANSLATE_KEYS.each_pair do |from, to|
          next unless hash.has_key?(from)
          hash[to] = hash[from]
          hash.delete(from)
        end
        hash
      end

      def green(text); color(text, "\e[32m"); end
      def red(text); color(text, "\e[31m"); end
      def yellow(text); color(text, "\e[33m"); end
      def blue(text); color(text, "\e[34m"); end

      def color(text, color_code)
        "#{color_code}#{text}\e[0m"
      end
    end

  end
end
