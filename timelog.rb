# -*- coding: utf-8 -*-
require 'json'
require 'set'

TIMEFILENAME = "timedb.txt"

EVENT = "event"
TIME = "time"
ID = "id"

EVENT_JOB_START = "Starting job"
EVENT_JOB_STOP = "Stopping job"
EVENT_DAY_START = "Starting day"
EVENT_DAY_PAUSE = "Starting pause"
EVENT_DAY_BACK = "Back from pause"
EVENT_DAY_STOP = "Stopping day"

class Timelog
  def initialize(timefilename)
    begin
      timedb = File.open(timefilename, 'r').read
    rescue Errno::ENOENT
      timedb = ''
    end
    if timedb.empty?
      @timedata = {}
    else
      begin
        @timedata = JSON.parse(timedb)
      rescue JSON::ParserError => e
        puts "Error parsing time data:"
        puts e.message
        exit!
      end
    end
    
    @timefilename = timefilename
    
    @jobs_in_progress = Set.new
    @day_status = :not_started
    day = get_day
    day.each do |map|
      event = map[EVENT]
      id = map[ID]
      case event
      when EVENT_JOB_START
        @jobs_in_progress.add(id)
      when EVENT_JOB_STOP
        @jobs_in_progress.delete(id)
      when EVENT_DAY_START
        @day_status = :started
      when EVENT_DAY_PAUSE
        @day_status = :on_pause
      when EVENT_DAY_BACK
        @day_status = :started
      when EVENT_DAY_STOP
        @day_status = :stopped
      end
    end
  end

  def get_time_now()
    # round the time into minutes to avoid weird inconsistencies
    # when displaying the times
    now = Time.now.to_i
    return now - now % 60
  end

  def is_time_integer?(str)
    sprintf("%02d", str.to_i) == str
  end

  def get_offset_from_param(offset)
    if offset.nil?
      return 0
    elsif offset.include? ":"
      # absolute time value
      parts = offset.split(":")
      if parts.length != 2
        puts "Invalid time offset"
        exit!
      end

      if not is_time_integer? parts[0] or not is_time_integer? parts[1]
        puts "Invalid time, use numbers!"
        exit!
      end

      h = parts[0].to_i
      m = parts[1].to_i
      if h < 0 or h > 23 or m < 0 or m > 59
        puts "Invalid time, use valid h:min values"
        exit!
      end
      now = get_time_now
      now_time = Time.at(now)
      given_time = Time.new(now_time.year, now_time.month, now_time.day, h, m)
      return given_time.to_i - now
    else
      # offset in minutes
      if not is_time_integer? offset
        puts "Invalid offset value, use full minutes"
        exit!
      end
      return offset*60
    end
  end


  def stop_job(id, offset)
    if @day_status == :on_pause
      puts "Can't stop jobs when on pause"
      exit!
    end
    if not @jobs_in_progress.include? id
      puts "No such job"
      return
    end
    day = get_day
    day.push({TIME=>get_time_now + get_offset_from_param(offset), EVENT=>EVENT_JOB_STOP, ID=>id})
    puts "Stopped job " + id
  end


  def start_job(id, offset)
    if @day_status != :started
      puts "Can't start jobs if the day is " + @day_status.to_s
      exit!
    end
    if not @jobs_in_progress.empty?
      if @jobs_in_progress.include? id
        puts "Job already started"
        exit!
      end

      #puts "Following jobs are in progress:"
      #@jobs_in_progress.each do |job|
      #  puts job
      #end
      #puts "Start in parallel? (y/n)> "
      #answer = $stdin.gets.chomp
      #alts = Set.new ['y', 'n']
      #while not alts.include? answer
      #  puts "(y/n) > "
      #  answer = $stdin.gets.chomp
      #end
      #if answer == 'n'
      @jobs_in_progress.each do |job|
        stop_job(job, offset)
      end
      #end
    end
    day = get_day
    day.push({TIME=>get_time_now + get_offset_from_param(offset), EVENT=>EVENT_JOB_START, ID=>id})
    puts "Started job " + id
  end


  def print_events()
    day = get_day
    day.each do |item|
      time = Time.at(item[TIME])
      hour = time.hour.to_s
      min = time.min.to_s
      event = item[EVENT]
      id = item[ID]
      
      printf "%02d:%02d - #{event} #{id}\n", hour, min
    end
  end


  def calculate_times(job_prefix)
    day = get_day
    jobs = {}
    current_start = -1
    total_day = 0
    total_pause = 0
    day_ended = false
    day.each do |item|
      time = item[TIME]
      event = item[EVENT]
      
      case event
      when EVENT_DAY_START
        current_start = time
      when EVENT_DAY_PAUSE
        total_day += time - current_start
        current_start = time
      when EVENT_DAY_BACK
        pause_length = time - current_start
        total_pause += pause_length
        current_start = time
        # remove pause from active jobs
        jobs.each_value do |job|
          if job[:active]
            job[:total_time] -= pause_length
          end
        end
      when EVENT_DAY_STOP
        total_day += time - current_start
        day_ended = true
      when EVENT_JOB_START
        id = item[ID]
        if not jobs.has_key? id
          jobs[id] = {:total_time => 0}
        end
        job = jobs[id]
        job[:active] = true
        job[:start_time] = time
      when EVENT_JOB_STOP
        id = item[ID]
        job = jobs[id]
        job[:active] = false
        job[:total_time] += time - job[:start_time]
      end
    end

    if not day_ended
      total_day += get_time_now - current_start
    end
    h_day = total_day / 3600
    m_day = (total_day % 3600) / 60
    h_pause = total_pause / 3600
    m_pause = (total_pause % 3600) / 60
    if not day_ended
      puts "Day so far: #{h_day}h #{m_day}min, pause: #{h_pause}h #{m_pause}min"
    else
      puts "Day: #{h_day}h #{m_day}min, pause: #{h_pause}h #{m_pause}min"
    end

    total_jobs = 0
    jobs.each_pair do |id, data|
      if data[:active]
        data[:total_time] += get_time_now - data[:start_time]
        h = data[:total_time] / 3600
        m = (data[:total_time] % 3600) / 60
        puts "Job \"#{id}\" still in progress, time until now: #{h}h #{m}min"
      else
        h = data[:total_time] / 3600
        m = (data[:total_time] % 3600) / 60
        puts "Job \"#{id}\": #{h}h #{m}min"
      end
      total_jobs += data[:total_time]
    end

    other_time = total_day - total_jobs
    if other_time > 0
      h = other_time / 3600
      m = (other_time % 3600) / 60
      puts "Unassigned time: #{h}h #{m}min"
    end

    # list all jobs that start with the given prefix
    if not job_prefix.nil?
      print "Job listing: "
      first = true
      jobs.each_pair do |id, data|
        if id.start_with? job_prefix
          if first
            first = false
          else
            print ", "
          end
          print id
        end
      end
      puts
    end
  end


  def start_day(offset)
    if @day_status != :not_started
      puts "Day already started."
      exit!
    end
    day = get_day
    day.push({TIME=>get_time_now + get_offset_from_param(offset), EVENT=>EVENT_DAY_START})
    @day_status = :started
    puts "Started the day"
    puts "Start a job (or leave empty not to): "
    answer = $stdin.gets.chomp
    if not answer.empty?
      start_job(answer, offset)
    end
  end

  def start_pause(offset)
    if @day_status != :started
      puts "Can't start a pause when day is " + @day_status.to_s
      exit!
    end
    day = get_day
    day.push({TIME=>get_time_now + get_offset_from_param(offset), EVENT=>EVENT_DAY_PAUSE})
    puts "Started a pause"
  end

  def stop_pause(offset)
    if @day_status != :on_pause
      puts "Can't end a pause when not having one. (Status: " + @day_status.to_s + ")"
      exit!
    end
    day = get_day
    day.push({TIME=>get_time_now + get_offset_from_param(offset), EVENT=>EVENT_DAY_BACK})
    puts "Back from pause"
  end

  def stop_day(offset)
    if not [:started, :on_pause].include? @day_status
      puts "Can't end a day when day is " + @day_status.to_s
      exit!
    end
    # end any active jobs
    @jobs_in_progress.each do |job|
      stop_job(job, offset)
    end
    day = get_day
    day.push({TIME=>get_time_now + get_offset_from_param(offset), EVENT=>EVENT_DAY_STOP})
    puts "Ended the day"
  end


  def get_day()
    now = Time.now
    yearkey = now.year.to_s
    monthkey = now.month.to_s
    daykey = now.mday.to_s

    if not @timedata.has_key? yearkey
      @timedata[yearkey] = {}
    end
    year = @timedata[yearkey]
    if not year.has_key? monthkey
      year[monthkey] = {}
    end
    month = year[monthkey]
    if not month.has_key? daykey
      month[daykey] = []
    end
    day = month[daykey]
  end  
  
  def write_time_data()
    timedb = File.open(@timefilename, 'w')
    timedb.write(JSON.generate(@timedata))
    timedb.write("\n")
    timedb.close
  end
  
end


def help()
  puts "Commands:"
  puts "job start|stop [id] [offset as min | time as hh:mm]"
  puts "day start|away|back|end [offset as min | time as hh:mm]"
  puts "print"
  puts "times [job prefix for listing]"
end

def check(x)
  if x.nil? or x.empty?
    help
    exit
  end
end



if __FILE__ == $0
  timelog = Timelog.new(TIMEFILENAME)

  cmd = ARGV[0]
  check(cmd)
  case cmd
  when 'day'
    arg1 = ARGV[1]
    check(arg1)
    case arg1
    when 'start'
      timelog.start_day(ARGV[2])
    when 'away'
      timelog.start_pause(ARGV[2])
    when 'back'
      timelog.stop_pause(ARGV[2])
    when 'end'
      timelog.stop_day(ARGV[2])
    else
      help
      exit!
    end

  when 'job'
    arg1 = ARGV[1]
    check(arg1)
    case arg1
    when 'start'
      check(ARGV[2])
      timelog.start_job(ARGV[2], ARGV[3])
    when 'stop'
      check(ARGV[2])
      timelog.stop_job(ARGV[2], ARGV[3])
    else
      help
      exit
    end
    
  when 'print'
    timelog.print_events()
    exit
  when 'times'
    timelog.calculate_times(ARGV[1])
    exit

  else
    help
    exit
  end
  timelog.write_time_data

end
