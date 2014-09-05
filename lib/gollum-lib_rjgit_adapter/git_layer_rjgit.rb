# ~*~ encoding: utf-8 ~*~

require 'rjgit'

module Gollum
  module Git

    import 'org.eclipse.jgit.revwalk.RevWalk'
    import 'org.eclipse.jgit.lib.ObjectId'
    
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
      
      def to_s
        @commit.id
      end
      
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
      
    end
    
    # Note that in Grit, the methods grep, rm, checkout, ls_files
    # are all passed to native via method_missing. Hence the uniform
    # method signatures.
    class Git
    
      def initialize(git)
        @git = git
      end
      
      def exist?
        @git.exist?
      end
      
      def grep(query, options={})
        ref = options[:ref] ? options[:ref] : "HEAD"
        blobs = []
        RJGit::Porcelain.ls_tree(@git.jrepo, nil, {:ref => ref, :recursive => true, :file_path => options[:path]}).each do |item|
          walk = RevWalk.new(@git.jrepo)
          blobs << RJGit::Blob.new(@git.jrepo, item[:mode], item[:path], walk.lookup_blob(ObjectId.from_string(item[:id]))) if item[:type] == 'blob'
        end
        result = []
        blobs.each do |blob|
          count = blob.data.downcase.scan(/#{query}/i).length
          result << {:name => blob.path, :count => count} if count > 0
        end
        result
      end
      
      # git.rm({'f' => true}, '--', path)
      def rm(options={}, *args, &block)
        @git.rm(options, *args, &block)
      end
      
      def checkout(path, ref, options = {}, &block)
        options[:paths] = [path]
        @git.checkout(ref, options)
      end
      
      # rev_list({:max_count=>1}, ref)
      def rev_list(options, *refs)
        raise "Not implemented"
      end
      
      def ls_files(query, options = {})
        ref = options[:ref] ? options[:ref] : "HEAD"
        result = RJGit::Porcelain.ls_tree(@git.jrepo, nil, {:ref => ref, :recursive => true, :file_path => options[:path]}).select {|object| object[:type] == "blob" && object[:path].split("/").last.scan(/#{query}/i) }
        result.map do |r|
          r[:path]
        end
      end
        
      def apply_patch(options={}, head_sha=nil, patch=nil)
        @git.apply_patch(options, head_sha, patch)
      end
      
      # @repo.git.cat_file({:p => true}, sha)
      def cat_file(options, sha)
        @git.cat_file(options, sha)
      end
      
      def log(path = nil, ref = nil, options = nil)
        @git.log(path, ref, options).map {|commit| Gollum::Git::Commit.new(commit)}
      end
      alias_method :versions_for_path, :log
      
      def refs(options, prefix)
        @git.refs(options, prefix)
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
      
      # index.commit(@options[:message], parents, actor, nil, @wiki.ref)
      def commit(message, parents = nil, actor = nil, last_tree = nil, head = nil)
        actor = actor ? actor.actor : RJGit::Actor.new("Gollum", "gollum@wiki")
        parents.map!{|parent| parent.commit} if parents
        commit_data = @index.commit(message, actor, parents, head)
        sha = commit_data[2]
        sha
      end
      
      def tree
        @index.treemap
      end
      
      def read_tree(id)
        walk = RevWalk.new(@index.jrepo)
          #begin
        @index.current_tree = RJGit::Tree.new(@index.jrepo, nil, nil, walk.lookup_tree(ObjectId.from_string(id)))
        #rescue
        #raise Gollum::Git::NoSuchShaFound
        #end
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
      def initialize(diff_entry)

      end
      def diff

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
        objectid = @repo.jrepo.resolve(ref)
        return nil if objectid.nil?
        id = objectid.name
        commit = @repo.find(id, :commit)
        return nil if commit.nil?
        Gollum::Git::Commit.new(commit)
        rescue Java::OrgEclipseJgitErrors::RevisionSyntaxException
          raise Gollum::Git::NoSuchShaFound
      end
      
      def commits(start = 'master', max_count = 10, skip = 0)
        @repo.commits(start, max_count).map{|commit| Gollum::Git::Commit.new(commit)}
      end
      
      # Not required by gollum-lib
      def find(sha, type)
        @repo.find(sha, type)
      end
      
      # @wiki.repo.head.commit.sha
      def head
        Gollum::Git::Ref.new("refs/heads/master", @repo.head)
      end
      
      def index
        @index ||= Gollum::Git::Index.new(RJGit::Plumbing::Index.new(@repo))
      end
      
      def log(commit = 'master', path = nil, options = {})
        git.log(path, commit, options)
      end
      
      def lstree(sha, options={})
        entries = RJGit::Porcelain.ls_tree(@repo.jrepo, @repo.find(sha, :tree), {:recursive => options[:recursive]})
        entries.map! do |entry| 
          entry[:mode] = entry[:mode].to_s(8)
          entry[:sha]  = entry[:id]
          entry
        end
      end
      
      def path
        @repo.path
      end
      
      def update_ref(head, commit_sha)
        @repo.update_ref(head, commit_sha)
      end

      def diff(sha1, sha2, path = nil)
        RJGit::Porcelain.diff(@repo, {:old_rev => sha2, :new_rev => sha1, :file_path => path, :patch => true})
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