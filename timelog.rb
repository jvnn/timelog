# -*- coding: utf-8 -*-
require 'json'
require 'set'

TIMEFILENAME = "timedb.txt"
MEMOFILENAME = "memo.txt"

EVENT = "event"
TIME = "time"
ID = "id"

EVENT_START = "Starting"
EVENT_STOP = "Stopping"


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
    day = get_day
    day.each do |map|
      event = map[EVENT]
      id = map[ID]
      if event == EVENT_START
        @jobs_in_progress.add(id)
      elsif event == EVENT_STOP
        @jobs_in_progress.delete(id)
      end
    end
  end


  def stop_job(id)
    if not @jobs_in_progress.include? id
      puts "No such job"
      return
    end
    day = get_day
    day.push({TIME=>Time.now.to_i, EVENT=>EVENT_STOP, ID=>id})
    @jobs_in_progress.delete(id)
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
      @jobs_in_progress.clear
    end
    @jobs_in_progress.add(id)
    day = get_day
    day.push({TIME=>Time.now.to_i, EVENT=>EVENT_START, ID=>id})
    puts "Started job " + id
  end


  def print_jobs()
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
  puts "job start|stop|print [id]"
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
    when 'print'
      timelog.print_jobs()
      exit
    else
      help
      exit
    end
  else
    help
    exit
  end
  timelog.write_time_data

end
