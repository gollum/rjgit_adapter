# ~*~ encoding: utf-8 ~*~

require 'rjgit'
require 'ostruct'

module Gollum

  def self.set_git_timeout(time)
  end

  def self.set_git_max_filesize(size)
  end

  module Git

    import 'org.eclipse.jgit.revwalk.RevWalk'
    import 'org.eclipse.jgit.lib.ObjectId'

    # Convert HEAD refspec to jgit canonical form
    def self.canonicalize(ref)
      return ref if sha?(ref)
      return "refs/heads/master" if ref.nil? || ref.to_s.upcase == "HEAD"
      result = ref.is_a?(Gollum::Git::Ref) ? ref.name : ref
      result = "refs/heads/#{result}" unless result =~ /^refs\/heads\//
      result
    end

    def self.sha?(str)
      !!(str =~ /^[0-9a-f]{40}$/)
    end
    
    class Actor
      
      attr_accessor :name, :email
      attr_reader :actor
      
      def initialize(name, email)
        @name = name
        @email = email
        @actor = RJGit::Actor.new(name, email)
      end
      
      def output(time)
        @actor.output(time)
      end
      
    end
    
    class Blob
      
      attr_reader :size
      
      # Gollum::Git::Blob.create(repo, :id => @sha, :name => name, :size => @size, :mode => @mode)
      def self.create(repo, options)
        blob = repo.find(options[:id], :blob)
        jblob = blob.jblob unless blob.nil?
        return nil if jblob.nil?
        blob = self.new(RJGit::Blob.new(repo.repo, options[:mode], options[:name], jblob))
        blob.set_size(options[:size]) if options[:size]
        return blob
      end
      
      def initialize(blob)
        @blob = blob
      end
      
      # Not required by gollum-lib. Should be private/protected?
      def set_size(size)
        @size = size
      end
      
      def id
        @blob.id
      end
      
      def mode
        @blob.mode
      end
      
      def data
        @blob.data
      end
      
      def name
        @blob.name
      end
      
      def mime_type
        @blob.mime_type
      end
      
      def is_symlink
        @blob.is_symlink?
      end

      def symlink_target(base_path = nil)
        target = @blob.data
        new_path = ::File.expand_path(::File.join('..', target), base_path)
        return new_path if ::File.file? new_path
        nil
      end
      
    end
    
    class Commit
      attr_reader :commit
      
      def initialize(commit)
        @commit = commit
      end
      
      def id
        @commit.id
      end
      alias_method :sha, :id
      alias_method :to_s, :id

      def author
        author = @commit.actor
        Gollum::Git::Actor.new(author.name, author.email)
      end
      
      def authored_date
        @commit.authored_date
      end
      
      def message
        @commit.message
      end
      
      def tree
        Gollum::Git::Tree.new(@commit.tree)
      end

      def stats
        return @stats unless @stats.nil?
        rjgit_stats = @commit.stats

        files = rjgit_stats[:files].map do |file|
          file[:new_file] == file[:old_file] if file[:new_file] == '/dev/null' # File is deleted, display only the original, deleted path.
          file.delete(:old_file) if (file[:old_file] == '/dev/null') || (file[:old_file] == file[:new_file]) # Don't include an old path when the file is new, or it's a regular update
          file
        end
        
        @stats = OpenStruct.new(
          :additions => rjgit_stats[:total_additions],
          :deletions => rjgit_stats[:total_deletions],
          :total => rjgit_stats[:total_additions] + rjgit_stats[:total_deletions],
          :files => files,
          :id => id
        )
      end
      
      def tracked_pathname
        begin
          @commit.tracked_pathname
        rescue NoMethodError
          nil
        end
      end
      
    end
    
    class Git
    
      def initialize(git)
        @git = git
      end
      
      def exist?
        ::File.exists?(@git.jrepo.getDirectory.to_s)
      end
      
      def grep(query, options={}, &block)
        ref = Gollum::Git.canonicalize(options[:ref])
        results = []
        walk = RevWalk.new(@git.jrepo)
        RJGit::Porcelain.ls_tree(@git.jrepo, options[:path], ref, {:recursive => true}).each do |item|
          if item[:type] == 'blob'
            blob = RJGit::Blob.new(@git.jrepo, item[:mode], item[:path], walk.lookup_blob(ObjectId.from_string(item[:id])))
            results << yield(blob.path, blob.binary? ? nil : blob.data)
          end
        end
        results.compact
      end
      
      def rm(path, options={})
        @git.remove(path)
      end
      
      def checkout(path, ref, options = {})
        ref = Gollum::Git.canonicalize(ref)
        options[:paths] = [path]
        options[:force] = true
        options[:commit] = "#{ref}^{commit}"
        @git.checkout(ref, options)
      end
      
      # rev_list({:max_count=>1}, ref)
      def rev_list(options, *refs)
        raise "Not implemented"
      end
      
      def ls_files(query, options = {})
        ref = Gollum::Git.canonicalize(options[:ref])
        result = RJGit::Porcelain.ls_tree(@git.jrepo, options[:path], ref, {:recursive => true}).select {|object| object[:type] == "blob" && !!(::File.basename(object[:path]) =~ /#{query}/i) }
        result.map do |r|
          r[:path]
        end
      end
      
      def apply_patch(sha, patch = nil, options = {})
        return false if patch.nil?
        begin
          @git.apply_patch(patch)
        rescue Java::OrgEclipseJgitApiErrors::PatchApplyException
          false
        end
        Tree.new(RJGit::Tree.new(@git.jrepo, nil, nil, RevWalk.new(@git.jrepo).lookup_tree(@git.jrepo.resolve("HEAD^{tree}"))))
      end
      
      # @repo.git.cat_file({:p => true}, sha)
      def cat_file(options, sha)
        @git.cat_file(options, sha)
      end
      
      def log(ref = 'refs/heads/master', path = nil, options = {})
        ref = Gollum::Git.canonicalize(ref)
        options[:list_renames] = true if path && options[:follow]
        @git.log(path, ref, options).map {|commit| Gollum::Git::Commit.new(commit)}
      end
      alias_method :versions_for_path, :log
      
      def refs(options, prefix)
        @git.refs(options, prefix)
      end

      def push(remote, branch, options = {})
        @git.push(remote, [branch].flatten, options)
      end

      def pull(remote, branch = nil, options = {})
        @git.pull(remote, branch, options)
      end
      
    end
    
    class Index
      
      def initialize(index)
        @index = index
        @current_tree = nil
      end
      
      def delete(path)
        @index.delete(path)
      end
      
      def add(path, data)
        @index.add(path, data)
      end
      
      def commit(message, parents = nil, actor = nil, last_tree = nil, ref = "refs/heads/master")
        ref = Gollum::Git.canonicalize(ref)
        actor = actor ? actor.actor : RJGit::Actor.new("Gollum", "gollum@wiki")
        parents = parents.map{|parent| parent.commit} if parents
        commit_data = @index.commit(message, actor, parents, ref)
        return false if !commit_data
        commit_data[2]
      end
      
      def tree
        @index.treemap
      end
      
      def read_tree(tree)
        tree = tree.id if tree.is_a?(Tree)
        begin
          @index.current_tree = RJGit::Tree.new(@index.jrepo, nil, nil, RevWalk.new(@index.jrepo).lookup_tree(@index.jrepo.resolve("#{tree}^{tree}")))
        rescue
          raise Gollum::Git::NoSuchShaFound
        end
        @current_tree = Gollum::Git::Tree.new(@index.current_tree)
      end
      
      def current_tree
        @current_tree
      end
      
    end
    
    class Ref
      def initialize(name, commit)
        @name, @commit = name, commit
      end
      
      def name
        @name
      end
      
      def commit
        Gollum::Git::Commit.new(@commit)
      end
            
    end

    class Diff
      def initialize(diff)
        @diff = diff[:patch].split("\n")[2..-1].join("\n")
      end
      def diff
        @diff
      end
    end
    
    class Repo
      
      attr_reader :repo
      
      def initialize(path, options = {})
        @repo = RJGit::Repo.new(path, options)
      end
      
      def self.init(path, git_options = {}, repo_options = {})
        RJGit::Repo.create(path, {:is_bare => false})
        self.new(path, {:is_bare => false})
      end
      
      def self.init_bare(path, git_options = {}, repo_options = {})
        RJGit::Repo.create(path, {:is_bare => true})
        self.new(path, {:is_bare => true})
      end
      
      def bare
        @repo.bare
      end
      
      def config
        @repo.config
      end
      
      def git
        @git ||= Gollum::Git::Git.new(@repo.git)
      end
      
      def commit(ref)
        ref = Gollum::Git.canonicalize(ref)
        objectid = @repo.jrepo.resolve(ref)
        return nil if objectid.nil?
        id = objectid.name
        commit = @repo.find(id, :commit)
        return nil if commit.nil?
        Gollum::Git::Commit.new(commit)
        rescue Java::OrgEclipseJgitErrors::RevisionSyntaxException
          raise Gollum::Git::NoSuchShaFound
      end
      
      def commits(ref = nil, max_count = 10, skip = 0)
        ref = Gollum::Git.canonicalize(ref)
        @repo.commits(ref, max_count).map{|commit| Gollum::Git::Commit.new(commit)}
      end
      
      # Not required by gollum-lib
      def find(sha, type)
        @repo.find(sha, type)
      end
      
      # @wiki.repo.head.commit.sha
      def head
        return nil unless @repo.head
        Gollum::Git::Ref.new("refs/heads/master", @repo.head)
      end
      
      def index
        @index ||= Gollum::Git::Index.new(RJGit::Plumbing::Index.new(@repo))
      end
      
      def log(ref = 'refs/heads/master', path = nil, options = {})
        commit = Gollum::Git.canonicalize(commit)
        git.log(ref, path, options)
      end
      
      def lstree(sha, options={})
        entries = RJGit::Porcelain.ls_tree(@repo.jrepo, nil, @repo.find(sha, :tree), {:recursive => options[:recursive]})
        entries.map! do |entry| 
          entry[:mode] = entry[:mode].to_s(8)
          entry[:sha]  = entry[:id]
          entry
        end
      end
      
      def path
        @repo.path
      end
      
      def update_ref(ref = "refs/heads/master", commit_sha)
        ref = Gollum::Git.canonicalize(head)
        cm = self.commit(commit_sha)
        @repo.update_ref(cm.commit, true, ref)
      end

      def diff(sha1, sha2, path = nil)
        RJGit::Porcelain.diff(@repo, {:old_rev => sha1, :new_rev => sha2, :file_path => path, :patch => true}).map {|d| Diff.new(d)}
      end
     
    end

    class Tree
      
      def initialize(tree)
        @tree = tree
      end
      
      def id
        @tree.id
      end
      
      def /(file)
        @tree.send(:/, file)
      end
      
      def blobs
        return Array.new if @tree == {}
        @tree.blobs.map{|blob| Gollum::Git::Blob.new(blob) }
      end
    end
    
    class NoSuchShaFound < StandardError
    end
    
  end
end
