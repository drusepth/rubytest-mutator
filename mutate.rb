#!/usr/bin/ruby

#readme


# Wrapper for a ruby test file, for timing execution, checking that all tests
# pass, and defining a fitness function for measurable improvements.
class TestFile
  attr_reader :file_path
  attr_accessor :last_execute_output, :detailed_last_execute_output

  def initialize path
    raise "File #{path} doesn't exist" unless File.file? path
    @file_path = path
  end

  def execute!
    raw_output = `ruby -Itest #{@file_path}`
    raw_output = raw_output.split(' ' * 6)
    raw_output.shift

    @last_execute_output = raw_output.map { |test_result| test_result.split("\e").first }
    @detailed_last_execute_output = raw_output
  end

  # higher = worse, lower = better
  def fitness
    (all_passing? ? 1 : 1000000) * (test_execution_time)
  end

  #private

  def test_execution_time
    start_time = Time.now
    execute!
    end_time = Time.now

    end_time - start_time
  end

  def all_passing?
    @last_execute_output ||= execute!
    @last_execute_output.all? { |test_result| test_result == "PASS" }
  end
end

# Mutator for ruby test files; defines source code mutations and permutates
# all possible combinations to find a result that keeps tests green and runs
# them faster than the original source.
class TestMutator
  attr_reader :file_path, :tests
  attr_accessor :original_source_code, :mutated_source_code, :best_source_code
  attr_accessor :original_fitness, :best_fitness
  attr_accessor :mutations

  def initialize path
    @file_path = path
    @original_source_code = File.read path
    @best_source_code = @original_source_code

    @tests = TestFile.new path
    @original_fitness = @tests.fitness
    @best_fitness = @original_fitness

    initialize_mutations!
  end

  def initialize_mutations!
    @mutations = []
    @mutations << Mutation.new('replace `create :sym` with `build :sym`', ->(source){
      source.gsub(/create!? (:[^\s]+)/, 'build \1')
    })
  end

  def mutate_source_code!
    # Mutate current source code
    @mutated_source_code = mutate @best_source_code

    # Write mutated source code to tmp file
    mutant_path = "/tmp/tc-#{('a'..'z').to_a.shuffle[0, 16].join}.rb"
    write_to_file mutant_path, @mutated_source_code

    # Compute fitness
    mutant_testfile = TestFile.new mutant_path
    mutant_fitness  = mutant_testfile.fitness

    # If the tests perform 5% better, replace the original source code
    if (mutant_fitness * 0.95) < @best_fitness
      puts "Better source code found! Tests fitness: #{mutant_fitness}"
      @best_source_code = @mutated_source_code
      @best_fitness     = mutant_fitness
      write_to_file @file_path, @mutated_source_code
    else
      puts "Failed mutation. Tests fitness: #{mutant_fitness}"
    end

    # Clean up tmp file
    File.delete mutant_path
  end

  #private

  class Mutation
    attr_accessor :descriptor, :mutator

    def initialize descriptor, mutator
      @descriptor = descriptor
      @mutator    = mutator
    end
  end

  def mutate source
    loop do
      mutation = @mutations.sample
      puts "Mutating #{mutation.descriptor}..."
      source = mutation.mutator.call source

      break if rand(0..1).zero?
    end

    source
  end

  def test_execution_time
    @tests.test_execution_time
  end

  def write_to_file path, contents
    puts "Writing file #{path}"
    File.open(path, 'w') { |file| file.write contents }
  end
end

# you only live once
def puts str
  super "\e[1m#{str}\e[22m"
end

test_file_path = ARGV.pop or abort "Usage: #{$0} path/to/test/file"

puts "Running tests first to compute original test execution time. This may take a minute."
mutator = TestMutator.new test_file_path
original_execution_time, new_execution_time = mutator.test_execution_time, nil
abort "Not all tests are passing! Make them green before trying this." unless mutator.tests.all_passing?

generations = 0
loop do
  generations += 1
  mutator.mutate_source_code!

  new_execution_time = mutator.test_execution_time
  break if new_execution_time <= (original_execution_time * 0.9)
  break if generations > 5
end

puts "Improved test execution time from #{original_execution_time} ms to #{new_execution_time} ms"
puts "New source code has been written to #{test_file_path}; see git diff for changes."
