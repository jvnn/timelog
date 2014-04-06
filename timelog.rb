# -*- coding: utf-8 -*-
require 'json'
require 'set'

TIMEFILENAME = "timedb.txt"
MEMOFILENAME = "memo.txt"

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
  def initialize(timefilename, memofilename)
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
      
    @memofilename = memofilename
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


  def stop_job(id)
    if not @jobs_in_progress.include? id
      puts "No such job"
      return
    end
    day = get_day
    day.push({TIME=>Time.now.to_i, EVENT=>EVENT_JOB_STOP, ID=>id})
    puts "Stopped job " + id
  end


  def start_job(id)
    if not @jobs_in_progress.empty?
      if @jobs_in_progress.include? id
        puts "Job already started"
        exit!
      end

      puts "Following jobs are in progress:"
      @jobs_in_progress.each do |job|
        puts job
      end
      puts "Start in parallel? (y/n)> "
      answer = $stdin.gets.chomp
      alts = Set.new ['y', 'n']
      while not alts.include? answer
        puts "(y/n) > "
        answer = $stdin.gets.chomp
      end
      if answer == 'n'
        @jobs_in_progress.each do |job|
          stop_job(job)
        end
      end
    end
    day = get_day
    day.push({TIME=>Time.now.to_i, EVENT=>EVENT_JOB_START, ID=>id})
    puts "Started job " + id
  end


  def print()
    day = get_day
    day.each do |item|
      time = Time.at(item[TIME])
      hour = time.hour.to_s
      min = time.min.to_s
      event = item[EVENT]
      id = item[ID]
      
      puts "#{hour}:#{min} - #{event} #{id}"
    end
  end


  def calculate_times()
    day = get_day
    jobs = {}
    current_start = -1
    total_day = 0
    total_pause = 0
    day_ended = false
    day.each do |item|
      time = item[TIME]
      event = item[EVENT]
      if [EVENT_JOB_START, EVENT_JOB_STOP].include? event
        id = item[ID]
        if not jobs.has_key? id
          jobs[id] = {}
        end
        jobs[id][time] = event
      else
        # day event
        case event
        when EVENT_DAY_START
          current_start = time
        when EVENT_DAY_PAUSE
          total_day += time - current_start
          current_start = time
        when EVENT_DAY_BACK
          total_pause += time - current_start
          current_start = time
        when EVENT_DAY_STOP
          total_day = time - current_start
          day_ended = true
        end
      end
    end

    if not day_ended
      total_day += Time.now.to_i - current_start
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

    jobs.each_pair do |id, times|
      total_time = 0
      current_start = -1
      times.keys.sort.each do |key|
        case times[key]
        when EVENT_JOB_START
          current_start = key
        when EVENT_JOB_STOP
          total_time += key - current_start
          current_start = -1
        end
      end

      if current_start > -1
        time_for_now = total_time + (Time.now.to_i - current_start)
        h = time_for_now / 3600
        m = (time_for_now % 3600) / 60
        puts "Job #{id} still in progress, time until now: #{h}h #{m}min"
      else
        h = total_time / 3600
        m = (total_time % 3600) / 60
        puts "Job #{id}: #{h}h #{m}min"
      end
    end
  end


  def start_day()
    if @day_status != :not_started
      puts "Day already started."
      exit!
    end
    day = get_day
    day.push({TIME=>Time.now.to_i, EVENT=>EVENT_DAY_START})
    puts "Started the day"
  end

  def start_pause()
    if @day_status != :started
      puts "Can't start a pause when day is " + @day_status.to_s
      exit!
    end
    day = get_day
    day.push({TIME=>Time.now.to_i, EVENT=>EVENT_DAY_PAUSE})
    puts "Started a pause"
  end

  def stop_pause()
    if @day_status != :on_pause
      puts "Can't end a pause when not having one. (Status: " + @day_status.to_s + ")"
      exit!
    end
    day = get_day
    day.push({TIME=>Time.now.to_i, EVENT=>EVENT_DAY_BACK})
    puts "Back from pause"
  end

  def stop_day(offset_min=0)
    if not [:started, :on_pause].include? @day_status
      puts "Can't end a day when day is " + @day_status.to_s
      exit!
    end
    day = get_day
    day.push({TIME=>Time.now.to_i + offset_min*60, EVENT=>EVENT_DAY_STOP})
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
  puts "job start|stop [id]"
  puts "day start|away|back|end [offset for day's end in minutes]"
  puts "print"
  puts "times"
end

def check(x)
  if x.nil? or x.empty?
    help
    exit
  end
end



if __FILE__ == $0
  timelog = Timelog.new(TIMEFILENAME, MEMOFILENAME)

  cmd = ARGV[0]
  check(cmd)
  case cmd
  when 'day'
    arg1 = ARGV[1]
    check(arg1)
    case arg1
    when 'start'
      timelog.start_day()
    when 'away'
      timelog.start_pause()
    when 'back'
      timelog.stop_pause()
    when 'end'
      timelog.stop_day(ARGV[2].to_i)
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
      timelog.start_job(ARGV[2])
    when 'stop'
      check(ARGV[2])
      timelog.stop_job(ARGV[2])
    else
      help
      exit
    end
    
  when 'print'
    timelog.print()
    exit
  when 'times'
    timelog.calculate_times()
    exit

  else
    help
    exit
  end
  timelog.write_time_data

end
