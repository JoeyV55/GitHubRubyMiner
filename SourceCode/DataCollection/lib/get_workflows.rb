# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'octokit'
require 'tty-spinner'

require_relative 'util/authenticate'
require_relative 'util/check_rate_limit'

def get_workflows(tokens)
  puts "\n======================================\n\nSTARTING GETWORKFLOWS\n\n===========================================\n"
  repository_does_not_exists = 0
  client = nil
  spinner = TTY::Spinner.new("[:spinner] Starting get_workflows...", format: :classic)
  client = check_rate_limit(client, 50, spinner, tokens)
  CSV.foreach('data/dataset_final.csv', headers: true) do |row|
    spinner = TTY::Spinner.new("[:spinner] Get #{row[0]} workflows ...", format: :classic)
    spinner.auto_spin

    begin
      client = check_rate_limit(client, 0, spinner, tokens)

      if client.repository?(row[0]) # if repository exists
        workflows = client.contents(row[0], path: '.github/workflows')

        workflows.each do |workflow|
          next unless File.extname(workflow.name) == '.yml' or File.extname(workflow.name) == '.yaml' # next unless a workflow file

          client = check_rate_limit(client, 10, spinner, tokens) # 10 call buffer
          commits = client.commits(row[0], path: ".github/workflows/#{workflow.name}")

          client = check_rate_limit(client, commits.count, spinner, tokens)

          commits.reverse_each do |commit|
              dest = "data/workflows/#{row[0]}/#{workflow.name}"
              date = "#{commit.commit.author.date.to_s.gsub(" ", "_").gsub(":", "-")}_#{workflow.name}"
              begin
                  file = client.contents(row[0], path: ".github/workflows/#{workflow.name}", ref: commit.sha)
              rescue StandardError # workflow file was deleted
                  FileUtils.mkdir_p dest unless File.exist?(dest)
                  File.open("#{dest}/#{date}", 'w') {|f| f.write('') }
                  next
              end
              enc = file.content
              plain = Base64.decode64(enc)
              FileUtils.mkdir_p dest unless File.exist?(dest)
              File.open("#{dest}/#{date}", 'w') {|f| f.write(plain) }
          end
        end
      else
        spinner.error("REPO DONT EXIST")
        repository_does_not_exists =+ 1
        next
      end
    rescue StandardError => error
      spinner.error(error.message)
      puts "\n=====================\nSTACK TRACE\n=================================\n"
      puts error.backtrace
      puts "\n\n\n\n\n\n"
      next
    end

    spinner.success
  end
end
