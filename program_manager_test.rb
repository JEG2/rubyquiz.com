require 'test/unit'
require 'program'
require 'program_manager'

class Numeric
  # Number of seconds since midnight
  def hours
    (self * 60).minutes
  end

  def minutes
    self * 60
  end

  def seconds
    self
  end

  alias_method :hour, :hours
  alias_method :minute, :minutes
  alias_method :second, :seconds
end

# We should record every Monday, between 8 and 9 PM, on channel 8
class WeeklyRepeatRecordingTest < Test::Unit::TestCase
  def setup
    @manager = ProgramManager.new
    @manager.add :start => 20.hours, :end => 21.hours,
                 :channel => 8, :days => %w(mon)
  end

  def test_does_not_record_on_tuesday
    assert_nil @manager.record?(Time.local(2006, 10, 31, 20, 0, 0))
  end

  def test_does_not_record_on_monday_prior_to_program
    assert_nil @manager.record?(Time.local(2006, 10, 30, 19, 55, 0))
  end

  def test_does_not_record_on_monday_after_program
    assert_nil @manager.record?(Time.local(2006, 10, 30, 21, 3, 0))
  end

  def test_records_between_specified_times
    (0 .. 59).each do |minute|
      assert_equal 8, @manager.record?(Time.local(2006, 10, 30, 20, minute, 0)),
          "At 20:#{sprintf('%02d', minute)}"
    end
  end
end

# Recording every Monday, from 8 to 9 PM as well as every Thursdays, from 7 to 10 PM.
class TwoWeeklyNonOverlappingRepeatingProgramsTest < Test::Unit::TestCase
  def setup
    @manager = ProgramManager.new

    @manager.add :start => 20.hours, :end => 21.hours,
                 :channel => 8, :days => %w(mon)
    @manager.add :start => 19.hours, :end => 22.hours,
                 :channel => 9, :days => %w(thu)
  end

  def test_records_on_mondays
    assert_equal 8, @manager.record?(Time.local(2006, 10, 30, 20, 17, 0))
  end

  def test_records_on_thursdays
    assert_equal 9, @manager.record?(Time.local(2006, 11, 2, 20, 17, 0))
  end

  def test_does_not_record_on_wednesdays
    assert_nil @manager.record?(Time.local(2006, 11, 1, 20, 17, 0))
  end
end

class WeeklyRepeatingAndOneShotProgramTest < Test::Unit::TestCase
  def setup
    @manager = ProgramManager.new

    @manager.add :start => 7.hours, :end => 8.hours + 30.minutes,
                 :channel => 7, :days => %w(sat)
    @manager.add :start => Time.local(2006, 11, 3, 20, 0, 0),
                 :end => Time.local(2006, 11, 3, 21, 0, 0), :channel => 3
  end

  def test_records_on_saturdays
    assert_equal 7, @manager.record?(Time.local(2006, 11, 4, 7, 23, 0))
  end

  def test_records_on_specific_date
    (Time.local(2006, 11, 3, 20, 0, 0) .. Time.local(2006, 11, 3, 21, 0, 0)).step(30.seconds) do |time|
      assert_equal 3, @manager.record?(time), "At #{time.strftime('%H:%M')}"
     end
  end

  def test_does_not_record_before_specific_date
    assert_nil @manager.record?(Time.local(2006, 11, 3, 19, 58, 0))
  end

  def test_does_not_record_before_after_date
    assert_nil @manager.record?(Time.local(2006, 11, 3, 21, 3, 0))
  end

  def test_does_not_record_on_same_weekday_next_week
    assert_nil @manager.record?(Time.local(2006, 11, 10, 20, 13, 0))
  end
end

class SpecificProgramOverlapsDailyProgram < Test::Unit::TestCase
  def setup
    @manager = ProgramManager.new

    @manager.add :start => 7.hours, :end => 8.hours + 30.minutes,
                 :channel => 13, :days => %w(mon tue wed thu fri)
    @manager.add :start => Time.local(2006, 11, 3, 8, 0, 0),
                 :end => Time.local(2006, 11, 3, 8, 30, 0), :channel => 3
  end

  def test_records_weekly_program_on_monday
    assert_equal 13, @manager.record?(Time.local(2006, 10, 30, 8, 12, 0))
  end

  def test_records_weekly_program_on_tuesday
    assert_equal 13, @manager.record?(Time.local(2006, 10, 31, 8, 12, 0))
  end

  def test_records_weekly_program_on_wednesday
    assert_equal 13, @manager.record?(Time.local(2006, 11, 1, 8, 12, 0))
  end

  def test_records_weekly_program_on_thursday
    assert_equal 13, @manager.record?(Time.local(2006, 11, 2, 8, 12, 0))
  end

  def test_records_more_specific_program_on_friday
    assert_equal 3, @manager.record?(Time.local(2006, 11, 3, 8, 12, 0))
  end

  def test_records_weekly_program_on_friday_until_specific_start
    (Time.local(2006, 11, 3, 7, 0, 0) .. Time.local(2006, 11, 3, 7, 59, 0)).step(30.second) do |time|
      assert_equal 13, @manager.record?(time)
    end
  end

  def test_switchover_to_specific_program_occurs_at_specific_start_exactly
    assert_equal 3, @manager.record?(Time.local(2006, 11, 3, 8, 0, 0))
  end

  def test_records_weekly_on_next_friday
    assert_equal 13, @manager.record?(Time.local(2006, 11, 10, 8, 0, 0))
  end
end

class TwoSpecificOverlappingProgramsProgram < Test::Unit::TestCase
  def setup
    @manager = ProgramManager.new

    @manager.add :start => Time.local(2006, 11, 3, 8, 0, 0),
                 :end => Time.local(2006, 11, 3, 12, 30, 0), :channel => 5
    @manager.add :start => Time.local(2006, 11, 3, 9, 0, 0),
                 :end => Time.local(2006, 11, 3, 10, 0, 0), :channel => 4
  end

  def test_records_prior_non_overlap
    (Time.local(2006, 11, 3, 8, 0, 0)  .. Time.local(2006, 11, 3, 8, 59, 0)).step(30.seconds) do |time|
      assert_equal 5, @manager.record?(time), time.strftime('%H:%M:%S')
    end
  end

  def test_records_post_non_overlap
    (Time.local(2006, 11, 3, 10, 1, 0) .. Time.local(2006, 11, 3, 12, 30, 0)).step(30.seconds) do |time|
      assert_equal 5, @manager.record?(time), time.strftime('%H:%M:%S')
    end
  end

  def test_records_most_recent_specific_program
    assert_equal 4, @manager.record?(Time.local(2006, 11, 3, 9, 54, 0))
  end
end
