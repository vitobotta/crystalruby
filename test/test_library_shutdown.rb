# frozen_string_literal: true

require_relative "test_helper"

class TestLibraryShutdown < Minitest::Test
  def test_shutdown_stops_a_running_library_once
    library = CrystalRuby::Library.allocate
    library.instance_variable_set(:@running, true)
    calls = []
    scheduler = ->(*args, **kwargs) { calls << [args, kwargs] }

    CrystalRuby::Reactor.stub(:schedule_work!, scheduler) do
      library.shutdown!
      library.shutdown!
    end

    assert_equal [[[library, :stop, :void], { blocking: true, async: false }]], calls
  end
end
