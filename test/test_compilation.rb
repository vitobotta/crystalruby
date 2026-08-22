# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestCompilation < Minitest::Test
  def setup
    @single_thread_mode = CrystalRuby.config.single_thread_mode
  end

  def teardown
    CrystalRuby.config.single_thread_mode = @single_thread_mode
  end

  def test_single_thread_mode_compiles_without_multithreaded_runtime
    CrystalRuby.config.single_thread_mode = true

    assert_includes compile_command, " -Dwithout_mt "
  end

  def test_multi_thread_mode_keeps_multithreaded_runtime
    CrystalRuby.config.single_thread_mode = false

    refute_includes compile_command, "-Dwithout_mt"
  end

  def test_compile_mode_is_part_of_library_digest
    Dir.mktmpdir do |directory|
      codegen_dir = Pathname(directory)
      File.write(codegen_dir / "index.cr", "require \"prelude\"\n")
      library = CrystalRuby::Library.allocate
      library.define_singleton_method(:codegen_dir) { codegen_dir }

      CrystalRuby.config.single_thread_mode = false
      multi_thread_digest = library.digest
      CrystalRuby.config.single_thread_mode = true

      refute_equal multi_thread_digest, library.digest
    end
  end

  private

  def compile_command
    CrystalRuby::Compilation.build_compile_command(
      verbose: false,
      debug: false,
      lib: "build/library.so",
      src: "src/library.cr"
    )
  end
end
