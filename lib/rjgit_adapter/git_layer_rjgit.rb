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
    import org.eclipse.jgit.lib.ConfigConstants

    BACKUP_DEFAULT_REF = 'refs/heads/master'

    def self.head_ref_name(repo)
      r = RJGit.repository_type(repo)
      begin
        # Mimic rugged's behavior: if HEAD points at a given ref, but that ref has no commits yet, return nil
        r.resolve('HEAD') ? r.getFullBranch : nil
      rescue Java::OrgEclipseJgitApiErrors::RefNotFoundException
        nil
      end
    end

    def self.global_default_branch
      org.eclipse.jgit.util.SystemReader.getInstance().getUserConfig().getString(ConfigConstants::CONFIG_INIT_SECTION, nil, ConfigConstants::CONFIG_KEY_DEFAULT_BRANCH)
    end

    def self.default_ref_for_repo(repo)
      self.head_ref_name(repo) || self.global_default_branch || BACKUP_DEFAULT_REF
    end

    # Don't touch if ref is a SHA or Git::Ref, otherwise convert it to jgit canonical form
    def self.canonicalize(ref)
      return ref if ref.is_a?(String) and sha?(ref)
      result = ref.is_a?(Gollum::Git::Ref) ? ref.name : ref
      (result =~ /^refs\/heads\// || result.upcase == 'HEAD') ? result : "refs/heads/#{result}"
    end

    def self.decanonicalize(ref_name)
      match = /^refs\/heads\/(.*)/.match(ref_name)
      match ? match[1] : nil
    end

    def self.sha?(str)
      !!(str =~ /^[0-9a-f]{40}$/)
    end
    
    class Actor

      attr_accessor :name, :email, :time
      attr_reader :actor

      def initialize(name, email, time = nil)
        @name = name
        @email = email
        @time = time
        @actor = RJGit::Actor.new(name, email, time)
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

      def parent
        @commit.parents.empty? ? nil : Gollum::Git::Commit.new(@commit.parents.first)
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
      
      def note(ref='refs/notes/commits')
        result = @commit.note(ref)
        result ? result.to_s : nil
      end

      def note=(msg, ref='refs/notes/commits')
        @commit.send(:note=,msg,ref)
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
        ref = options[:ref] ?  Gollum::Git.canonicalize(options[:ref]) : Gollum::Git.default_ref_for_repo(@git.jrepo)
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
        options[:commit] = if ref == 'HEAD'
          "#{Gollum::Git.default_ref_for_repo(@git.jrepo)}"
        else
          "#{Gollum::Git.canonicalize(ref)}}"
        end
        options[:paths] = [path]
        options[:force] = true
        @git.checkout(ref, options)
      end
      
      # rev_list({:max_count=>1}, ref)
      def rev_list(options, *refs)
        raise 'Not implemented'
      end
      
      def ls_files(query, options = {})
        ref = Gollum::Git.canonicalize(options[:ref])
        result = RJGit::Porcelain.ls_tree(@git.jrepo, options[:path], ref, {:recursive => true}).select {|object| object[:type] == 'blob' && !!(::File.basename(object[:path]) =~ /#{query}/i) }
        result.map do |r|
          r[:path]
        end
      end
      
      def revert_path(path, sha1, sha2, ref = Gollum::Git.default_ref_for_repo(@git.jrepo))
        result, _paths = revert(path, sha1, sha2, ref)
        result
      end
      
      def revert_commit(sha1, sha2, ref = Gollum::Git.default_ref_for_repo(@git.jrepo))
        revert(nil, sha1, sha2, ref)
      end
      
      def revert(path, sha1, sha2, ref = Gollum::Git.default_ref_for_repo(@git.jrepo))
        patch = generate_patch(sha1, sha2, path)
        return false unless patch
        begin
          applier = RJGit::Plumbing::ApplyPatchToIndex.new(@git.jrepo, patch, ref)
          applier.new_tree
        rescue ::RJGit::PatchApplyException
          false
        end
      end
            
      # @repo.git.cat_file({:p => true}, sha)
      def cat_file(options, sha)
        @git.cat_file(options, sha)
      end
      
      def log(ref = Gollum::Git.default_ref_for_repo(@git.jrepo), path = nil, options = {})
        options[:list_renames] = true if path && options[:follow]
        @git.log(path, Gollum::Git.canonicalize(ref), options).map {|commit| Gollum::Git::Commit.new(commit)}
      end
      
      def versions_for_path(path, ref, options)
        log(ref, path, options)
      end
      
      def refs(options, prefix)
        @git.refs(options, prefix)
      end

      def push(remote, branch, options = {})
        @git.push(remote, [branch].flatten, options)
      end

      def pull(remote, branch = nil, options = {})
        @git.pull(remote, branch, options)
      end
      
      private
            
      def generate_patch(sha1, sha2, path = nil)
        RJGit::Plumbing::ApplyPatchToIndex.diffs_to_patch(RJGit::Porcelain.diff(@git.jrepo, patch: true, new_rev: sha1, old_rev: sha2, file_path: path))
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
      
      def commit(message, parents = nil, actor = nil, last_tree = nil, ref = Gollum::Git.default_ref_for_repo(@index.jrepo))
        actor = actor ? actor.actor : RJGit::Actor.new('Gollum', 'gollum@wiki')
        parents = parents.map{|parent| parent.commit} if parents
        commit_data = @index.commit(message, actor, parents, Gollum::Git.canonicalize(ref))
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
      def initialize(commit, name)
        @commit, @name = commit, name
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
        objectid = @repo.jrepo.resolve(Gollum::Git.canonicalize(ref))
        return nil if objectid.nil?
        id = objectid.name
        commit = @repo.find(id, :commit)
        return nil if commit.nil?
        Gollum::Git::Commit.new(commit)
        rescue Java::OrgEclipseJgitErrors::RevisionSyntaxException
          raise Gollum::Git::NoSuchShaFound
      end
      
      def commits(ref = Gollum::Git.default_ref_for_repo(@repo), max_count = 10, skip = 0)
        @repo.commits(ref, max_count).map{|commit| Gollum::Git::Commit.new(commit)}
      end
      
      # Not required by gollum-lib
      def find(sha, type)
        @repo.find(sha, type)
      end
      
      # @wiki.repo.head.commit.sha
      def head
        return nil unless @repo.head
        Gollum::Git::Ref.new(@repo.head, Gollum::Git.head_ref_name(@repo))
      end
      
      def index
        @index ||= Gollum::Git::Index.new(RJGit::Plumbing::Index.new(@repo))
      end
      
      def log(ref = Gollum::Git.default_ref_for_repo(@repo), path = nil, options = {})
        git.log(Gollum::Git.canonicalize(ref), path, options)
      end
      
      def lstree(sha, options={})
        entries = RJGit::Porcelain.ls_tree(@repo.jrepo, nil, @repo.find(sha, :tree), {:recursive => options[:recursive]})
        entries.map! do |entry| 
          entry[:mode] = entry[:mode]
          entry[:sha]  = entry[:id]
          entry
        end
      end
      
      def path
        @repo.path
      end
      
      def update_ref(ref, commit_sha)
        cm = self.commit(commit_sha)
        @repo.update_ref(cm.commit, true, Gollum::Git.canonicalize(ref))
      end

      def diff(sha1, sha2, path = nil)
        RJGit::Porcelain.diff(@repo, {:old_rev => sha1, :new_rev => sha2, :file_path => path, :patch => true}).inject("") {|result, diff| result << diff[:patch]}
      end

      # Find the first existing branch in an Array of branch names of the form ['main', ...] and return its String name.
      def find_branch(search_list)
        search_list.find do |branch_name|
          @repo.branches.find do |canonical_name|
            Gollum::Git.decanonicalize(canonical_name) == branch_name
          end
        end
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

      def find_blob(&block)
        return nil unless block_given?
        @tree.find_blob(&block)
      end
    end
    
    class NoSuchShaFound < StandardError
    end
    
  end
end
