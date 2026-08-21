# frozen_string_literal: true

require_relative "test_helper"

class TestCompilerFreeRuntime < Minitest::Test
  def test_existing_library_does_not_require_shards_without_compiler
    previous = CrystalRuby.config.crystal_missing_ignore
    library = CrystalRuby::Library.new("compiler-free-runtime-test")
    CrystalRuby.config.crystal_missing_ignore = true

    library.stub(:lib_file, Pathname("/compiled/library")) do
      File.stub(:exist?, true) do
        CrystalRuby::Compilation.stub(:shard_check?, ->(*) { raise "unexpected shard check" }) do
          assert library.shards_installed?
        end
      end
    end
  ensure
    CrystalRuby.config.crystal_missing_ignore = previous
  end
end
