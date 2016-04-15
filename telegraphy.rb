#!/usr/bin/env ruby

# ======== INCLUDES ========

require 'sinatra'
require 'json'
require 'slim'
require 'rugged'
include Rugged

# ======== CONSTANTS AND GLOBALS ========

GIT_DIR = 'data/workdir'
REMOTE = 'origin'
BRANCH = 'master'
$repo = Repository.new(GIT_DIR)

# ======== HELPERS ========

# Update the git repository
def updateRepo()
  $repo.checkout(BRANCH)

  # fetch
  remote = $repo.remotes['' << REMOTE]
  remote.fetch()

  # merge
  distant_commit = $repo.branches['' << REMOTE << '/' << BRANCH].target
  $repo.references.update($repo.head, distant_commit.oid)
end

# Create the options with the current date for commit
def createOptions(file, action)
  options = {}
  options[:tree] = $repo.index.write_tree($repo)
  options[:author] = { :email => "telegraphy@git.com", :name => 'Telegraphy', :time => Time.now }
  options[:committer] = { :email => "telegraphy@git.com", :name => 'Telegraphy', :time => Time.now }
  options[:message] ||= "#{action} #{file} from Telegraphy."
  options[:parents] = $repo.empty? ? [] : [ $repo.head.target ].compact
  options[:update_ref] = 'HEAD'
  return options
end

# ======== ROUTES ========

# Return the HMTL index
get '/' do
  slim :index
end

# Return JSON object with the list of available files
get '/files' do
  files = []
  begin
    updateRepo()
    tree = $repo.lookup($repo.head.target_id).tree
    tree.map { |f| files.push(f) }
  rescue ReferenceError
  end
  files.to_json
end

# Return JSON object with the content of the given file
get '/files/:file' do |file|
  begin
    updateRepo()
    tree = $repo.lookup($repo.head.target_id).tree
    blob = tree.find { |f| f[:name] == file }
    file = $repo.lookup(blob[:oid])
    {
      name: blob[:name], 
      oid: blob[:oid], 
      content: file.content
    }.to_json
  rescue NoMethodError
    halt 404
  rescue ReferenceError
    halt 404
  end
end

# Create a new empty file
put '/files/:file' do |file|
  begin
    updateRepo()
    $repo.index.read_tree($repo.head.target.tree)

    tree = $repo.lookup($repo.head.target_id).tree
    blob = tree.find { |f| f[:name] == file }
    halt 304 unless blob.nil?
  rescue ReferenceError
    # Empty repository
  end

  oid = $repo.write("", :blob)
  $repo.index.add(:path => file, :oid => oid, :mode => 0100644)

  Commit.create($repo, createOptions(file, "Create"))
  $repo.push REMOTE, ['refs/heads/' << BRANCH]
end

# Modify the content of the file
post '/files/:file' do |file|
  halt 405 if @request.params['content'].nil?
  
  oid = $repo.write(@request.params['content'].gsub(/\r\n/, "\n"), :blob)

  begin
    updateRepo()
    $repo.index.read_tree($repo.head.target.tree)
  rescue ReferenceError
    # Empty repository
  end

  $repo.index.add(:path => file, :oid => oid, :mode => 0100644)

  Commit.create($repo, createOptions(file, "Update"))
  $repo.push REMOTE, ['refs/heads/' << BRANCH]
end
