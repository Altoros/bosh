require 'securerandom'
require 'spec_helper'

describe 'cli releases', type: :integration do
  with_reset_sandbox_before_each

  # <9s
  it 'cannot create a final release without the blobstore secret', no_reset: true do
    Dir.chdir(TEST_RELEASE_DIR) do
      FileUtils.rm_rf('dev_releases')

      # We switched to using a local provider in the template, so move in a config from elsewhere
      FileUtils.cp(spec_asset('blobstore_config_requiring_credentials.yml'), 'config/final.yml')

      out = bosh_runner.run_in_current_dir('create release --final', failure_expected: true)
      expect(out).to match(/Can't create final release without blobstore secret/)
    end
  end

  it 'allows creation of new final releases with the same content as the latest final release' do
    Dir.chdir(TEST_RELEASE_DIR) do
      out = bosh_runner.run_in_current_dir('create release --final', failure_expected: false)
      expect(out).to match(/Release version: 1/)

      out = bosh_runner.run_in_current_dir('create release --final --force', failure_expected: false)
      expect(out).to match(/Release version: 2/)

      out = bosh_runner.run_in_current_dir('create release --final --force', failure_expected: false)
      expect(out).to match(/Release version: 3/)
    end
  end

  it 'allows creation of new dev releases with the same content as the latest dev release' do
    Dir.chdir(TEST_RELEASE_DIR) do
      out = bosh_runner.run_in_current_dir('create release', failure_expected: false)
      expect(out).to match(/Release version: 0\+dev.1/)

      out = bosh_runner.run_in_current_dir('create release --force', failure_expected: false)
      expect(out).to match(/Release version: 0\+dev.2/)

      out = bosh_runner.run_in_current_dir('create release --force', failure_expected: false)
      expect(out).to match(/Release version: 0\+dev.3/)
    end
  end

  it 'allows creation of new final releases with the same content as a previous final release' do
    Dir.chdir(TEST_RELEASE_DIR) do
      out = bosh_runner.run_in_current_dir('create release --final', failure_expected: false)
      expect(out).to match(/Release version: 1/)

      with_changed_release do
        out = bosh_runner.run_in_current_dir('create release --final --force', failure_expected: false)
        expect(out).to match(/Release version: 2/)
      end

      out = bosh_runner.run_in_current_dir('create release --final --force', failure_expected: false)
      expect(out).to match(/Release version: 3/)
    end
  end

  it 'allows creation of new dev releases with the same content as a previous dev release' do
    Dir.chdir(TEST_RELEASE_DIR) do
      out = bosh_runner.run_in_current_dir('create release', failure_expected: false)
      expect(out).to match(/Release version: 0\+dev.1/)

      with_changed_release do
        out = bosh_runner.run_in_current_dir('create release --force', failure_expected: false)
        expect(out).to match(/Release version: 0\+dev.2/)
      end

      out = bosh_runner.run_in_current_dir('create release --force', failure_expected: false)
      expect(out).to match(/Release version: 0\+dev.3/)
    end
  end

  it 'allows creation of a final release without an existing dev release', no_reset: false do
    Dir.chdir(TEST_RELEASE_DIR) do
      expect(File.exist?('releases/bosh-release-1.yml')).to eq(false)

      out = bosh_runner.run_in_current_dir('create release --final', failure_expected: false)
      expect(out).to_not match(/Please consider creating a dev release first/)

      expect(Dir.exist?('dev_releases')).to eq(false)
      expect(File.exist?('releases/bosh-release-1.yml')).to eq(true)
    end
  end

  it 'allows creation of new final release without .gitignore files' do
    Dir.chdir(TEST_RELEASE_DIR) do
      out = bosh_runner.run_in_current_dir('create release --final', failure_expected: false)
      expect(out).to match(/Release version: 1/)

      `git add .`
      `git commit -m 'final release 1'`
      `git clean -fdx`

      out = bosh_runner.run_in_current_dir('create release --final --force', failure_expected: false)
      expect(out).to match(/Release version: 2/)
    end
  end

  context 'when no previous releases have been made' do
    it 'final release uploads the job & package blobs' do
      Dir.chdir(TEST_RELEASE_DIR) do
        expect(File.exist?('releases/bosh-release-1.yml')).to eq(false)

        out = bosh_runner.run_in_current_dir('create release --final', failure_expected: false)
        expect(out).to match(/Uploaded, blobstore id/)
        expect(out).to_not match(/This package has already been uploaded/)
      end
    end
  end

  it 'creates a new final release with a default version' do
    release_1 = File.join(TEST_RELEASE_DIR, 'releases/bosh-release-1.yml')
    release_2 = File.join(TEST_RELEASE_DIR, 'releases/bosh-release-2.yml')

    Dir.chdir(TEST_RELEASE_DIR) do
      File.open('config/final.yml', 'w') do |final|
        final.puts YAML.dump(
          'blobstore' => {
            'provider' => 'local',
            'options' => { 'blobstore_path' => current_sandbox.blobstore_storage_dir },
          },

        )
      end
      File.open('config/private.yml', 'w') do |final|
        final.puts YAML.dump(
          'blobstore_secret' => 'something',
          'blobstore' => {
            'local' => {},
          },
        )
      end

      bosh_runner.run_in_current_dir('create release --force')
      bosh_runner.run_in_current_dir('create release --final --force')
      expect(File.exists?(release_1)).to be(true)

      # modify a release file to force a new version
      `echo ' ' >> #{File.join(TEST_RELEASE_DIR, 'jobs', 'foobar', 'templates', 'foobar_ctl')}`
      bosh_runner.run_in_current_dir('create release --force')
      bosh_runner.run_in_current_dir('create release --final --force')
      expect(File.exists?(release_2)).to be(true)
    end
  end

  it 'creates and deploys a new final release with a user defined version' do
    target_and_login

    commit_hash = ''

    Dir.chdir(TEST_RELEASE_DIR) do
      dev_release_1 = File.join('dev_releases/bosh-release-0+dev.1.yml')
      release_1 = File.join('releases/bosh-release-1.0.yml')
      dev_release_2 = File.join('dev_releases/bosh-release-1.0+dev.1.yml')
      release_2 = File.join('releases/bosh-release-2.0.yml')

      File.open('config/final.yml', 'w') do |final|
        final.puts YAML.dump(
          'blobstore' => {
            'provider' => 'local',
            'options' => { 'blobstore_path' => current_sandbox.blobstore_storage_dir },
          },
        )
      end

      File.open('config/private.yml', 'w') do |final|
        final.puts YAML.dump(
          'blobstore_secret' => 'something',
          'blobstore' => {
            'local' => {},
          },
        )
      end

      bosh_runner.run_in_current_dir('create release --force')
      expect(Dir[File.join('dev_releases/bosh-release-*.yml')]).to eq([dev_release_1])
      bosh_runner.run_in_current_dir('create release --final --force --version 1.0')
      expect(Dir[File.join('releases/bosh-release-*.yml')]).to eq([release_1])

      with_changed_release do
        bosh_runner.run_in_current_dir('create release --force')
        expect(Dir[File.join('dev_releases/bosh-release-*.yml')].sort).to eq([dev_release_1, dev_release_2].sort)
        bosh_runner.run_in_current_dir('create release --final --force --version 2.0')
        expect(Dir[File.join('releases/bosh-release-*.yml')].sort).to eq([release_1, release_2].sort)
      end
      bosh_runner.run_in_current_dir('upload release')

      commit_hash = `git show-ref --head --hash=8 2> /dev/null`.split.first
    end

    bosh_runner.run("upload stemcell #{spec_asset('valid_stemcell.tgz')}")

    manifest = Bosh::Spec::Deployments.simple_manifest
    manifest['releases'].first['version'] = 'latest'

    deployment_manifest = yaml_file('simple', manifest)
    bosh_runner.run("deployment #{deployment_manifest.path}")

    bosh_runner.run('deploy')

    expect_output('releases', <<-OUT)
    +--------------+----------+-------------+
    | Name         | Versions | Commit Hash |
    +--------------+----------+-------------+
    | bosh-release | 2.0*     | #{commit_hash}+   |
    +--------------+----------+-------------+
    (*) Currently deployed
    (+) Uncommitted changes

    Releases total: 1
    OUT
  end

  # ~31s
  it 'can upload a release' do
    release_filename = spec_asset('valid_release.tgz')

    target_and_login
    out = bosh_runner.run("upload release #{release_filename}")

    expect(out).to match /release uploaded/i

    out = bosh_runner.run('releases')
    expect(out).to match /releases total: 1/i
    expect(out).to match /appcloud.+0\.1/
  end

  # ~33s
  it 'uploads the latest generated release if no release path given' do
    Dir.chdir(TEST_RELEASE_DIR) do
      FileUtils.rm_rf('dev_releases')

      bosh_runner.run_in_current_dir('create release')
      target_and_login
      bosh_runner.run_in_current_dir('upload release')
    end

    out = bosh_runner.run('releases')
    expect(out).to match /bosh-release.+0\+dev\.1/
  end

  # ~41s
  it 'sparsely uploads the release' do
    release_1 = File.join(TEST_RELEASE_DIR, 'dev_releases/bosh-release-0+dev.1.tgz')
    release_2 = File.join(TEST_RELEASE_DIR, 'dev_releases/bosh-release-0+dev.2.tgz')

    Dir.chdir(TEST_RELEASE_DIR) do
      FileUtils.rm_rf('dev_releases')

      bosh_runner.run_in_current_dir('create release --with-tarball')
      expect(File.exists?(release_1)).to be(true)
    end

    target_and_login
    bosh_runner.run("upload release #{release_1}")

    Dir.chdir(TEST_RELEASE_DIR) do
      new_file = File.join('src', 'bar', 'bla')
      begin
        FileUtils.touch(new_file)

        bosh_runner.run_in_current_dir('create release --force --with-tarball')
        expect(File.exists?(release_2)).to be(true)
      ensure
        FileUtils.rm_rf(new_file)
      end
    end

    out = bosh_runner.run("upload release #{release_2}")
    expect(out).to match /Checking if can repack release for faster upload/
    expect(out).to match /foo\s*\(.*\)\s*SKIP/
    expect(out).to match /foobar\s*\(.*\)\s*UPLOAD/
    expect(out).to match /bar\s*\(.*\)\s*UPLOAD/
    expect(out).to match /Release repacked/
    expect(out).to match /Started creating new packages > bar.*Done/
    expect(out).to match /Started processing 4 existing packages > Processing 4 existing packages.*Done/
    expect(out).to match /Started processing 4 existing jobs > Processing 4 existing jobs.*Done/
    expect(out).to match /Release uploaded/

    out = bosh_runner.run('releases')
    expect(out).to match /releases total: 1/i
    expect(out).to match /bosh-release.+0\+dev\.1.*0\+dev\.2/m
  end

  # ~9s
  it 'cannot upload malformed release', no_reset: true do
    target_and_login

    release_filename = spec_asset('release_invalid_checksum.tgz')
    out = bosh_runner.run("upload release #{release_filename}", failure_expected: true)
    expect(out).to match /Release is invalid, please fix, verify and upload again/
  end

  it 'fails to upload a release that is already uploaded' do
    release_filename = spec_asset('valid_release.tgz')

    target_and_login
    bosh_runner.run("upload release #{release_filename}")
    out = bosh_runner.run("upload release #{release_filename}", failure_expected: true)

    expect(out).to match 'This release version has already been uploaded'
  end

  # ~32s
  it 'marks releases that have uncommitted changes' do
    release_1 = File.join(TEST_RELEASE_DIR, 'dev_releases/bosh-release-0+dev.1.yml')
    commit_hash = ''

    Dir.chdir(TEST_RELEASE_DIR) do
      commit_hash = `git show-ref --head --hash=8 2> /dev/null`.split.first

      new_file = File.join('src', 'bar', 'bla')
      FileUtils.touch(new_file)
      bosh_runner.run_in_current_dir('create release --force')
      FileUtils.rm_rf(new_file)
      expect(File.exists?(release_1)).to be(true)
      release_manifest = Psych.load_file(release_1)
      expect(release_manifest['commit_hash']).to eq commit_hash
      expect(release_manifest['uncommitted_changes']).to be(true)

      target_and_login
      bosh_runner.run_in_current_dir('upload release')
    end

    expect_output('releases', <<-OUT)
    +--------------+----------+-------------+
    | Name         | Versions | Commit Hash |
    +--------------+----------+-------------+
    | bosh-release | 0+dev.1  | #{commit_hash}+   |
    +--------------+----------+-------------+
    (+) Uncommitted changes

    Releases total: 1
    OUT
  end

  # ~25s
  it 'allows deleting a whole release' do
    target_and_login

    release_filename = spec_asset('valid_release.tgz')
    bosh_runner.run("upload release #{release_filename}")

    out = bosh_runner.run('delete release appcloud')
    expect(out).to match regexp('Deleted `appcloud')

    expect_output('releases', <<-OUT)
    No releases
    OUT
  end

  # ~22s
  it 'allows deleting a particular release version' do
    target_and_login

    release_filename = spec_asset('valid_release.tgz')
    bosh_runner.run("upload release #{release_filename}")

    out = bosh_runner.run('delete release appcloud 0.1')
    expect(out).to match regexp('Deleted `appcloud/0.1')
  end

  it 'fails to delete release in use but deletes a different release' do
    target_and_login

    Dir.chdir(TEST_RELEASE_DIR) do
      bosh_runner.run_in_current_dir('create release')
      bosh_runner.run_in_current_dir('upload release')

      # change something in TEST_RELEASE_DIR
      FileUtils.touch(File.join('src', 'bar', 'pretend_something_changed'))

      bosh_runner.run_in_current_dir('create release --force')
      bosh_runner.run_in_current_dir('upload release')
    end

    bosh_runner.run("upload stemcell #{spec_asset('valid_stemcell.tgz')}")

    deployment_manifest = yaml_file('simple', Bosh::Spec::Deployments.simple_manifest)
    bosh_runner.run("deployment #{deployment_manifest.path}")

    bosh_runner.run('deploy')

    out = bosh_runner.run('delete release bosh-release', failure_expected: true)
    expect(out).to match /Error 30007: Release `bosh-release' is still in use/

    out = bosh_runner.run('delete release bosh-release 0.2-dev')
    expect(out).to match %r{Deleted `bosh-release/0.2-dev'}
  end

  # ~57s
  it 'release lifecycle: create, upload, update (w/sparse upload), delete' do
    commit_hash = ''

    Dir.chdir(TEST_RELEASE_DIR) do
      release_1 = File.join('dev_releases/bosh-release-0+dev.1.yml')
      release_2 = File.join('dev_releases/bosh-release-0+dev.2.yml')

      commit_hash = `git show-ref --head --hash=8 2> /dev/null`.split.first

      bosh_runner.run_in_current_dir('create release')
      expect(File.exists?(release_1)).to be(true)

      target_and_login
      bosh_runner.run_in_current_dir("upload release #{release_1}")

      with_changed_release do
        #  In an ephemeral git repo
        `git add .`
        `git commit -m 'second dev release'`
        expect(File.exists?(release_1)).to be(true)

        bosh_runner.run_in_current_dir('create release')
        expect(File.exists?(release_2)).to be(true)
      end

      out = bosh_runner.run_in_current_dir("upload release #{release_2}")
      expect(out).to match regexp('Building tarball')
      expect(out).not_to match regexp('Checking if can repack')
      expect(out).not_to match regexp('Release repacked')
      expect(out).to match /Release uploaded/
    end

    out = bosh_runner.run('releases')
    expect(out).to match /releases total: 1/i
    expect(out).to match /bosh-release.+0\+dev\.1.*0\+dev\.2/m

    bosh_runner.run('delete release bosh-release 0+dev.2')
    expect_output('releases', <<-OUT)
    +--------------+----------+-------------+
    | Name         | Versions | Commit Hash |
    +--------------+----------+-------------+
    | bosh-release | 0+dev.1  | #{commit_hash}    |
    +--------------+----------+-------------+

    Releases total: 1
    OUT

    bosh_runner.run('delete release bosh-release 0+dev.1')
    expect_output('releases', <<-OUT )
    No releases
    OUT
  end

  it 'verifies a sample valid release', no_reset: true do
    release_filename = spec_asset('valid_release.tgz')
    out = bosh_runner.run("verify release #{release_filename}")
    expect(out).to match(regexp("`#{release_filename}' is a valid release"))
  end

  it 'points to an error on invalid release', no_reset: true do
    release_filename = spec_asset('release_invalid_checksum.tgz')
    out = bosh_runner.run("verify release #{release_filename}", failure_expected: true)
    expect(out).to match(regexp("`#{release_filename}' is not a valid release"))
  end

  it 'does include excluded files' do
    Dir.chdir(TEST_RELEASE_DIR) do
      release_tarball = File.join(TEST_RELEASE_DIR, 'dev_releases/bosh-release-0+dev.1.tgz')

      FileUtils.rm_rf('dev_releases')

      bosh_runner.run_in_current_dir('create release --with-tarball')
      Dir.mktmpdir do |temp_dir|
        `tar xzf #{release_tarball} -C #{temp_dir}`
        foo_package = File.join(temp_dir, 'packages', 'foo.tgz')
        release_file_list = `tar -tzf #{foo_package}`
        expect(release_file_list).to_not include('excluded_file')
        expect(release_file_list).to include('foo')
      end
    end
  end

  describe 'uploading a release that already exists' do
    before { target_and_login }

    context 'when the release is local' do
      let(:local_release_path) { spec_asset('valid_release.tgz') }
      before { bosh_runner.run("upload release #{local_release_path}") }

      context 'when using the --skip-if-exists flag' do
        it 'tells the user and does not exit as a failure' do
          output = bosh_runner.run("upload release #{local_release_path} --skip-if-exists")
          expect(output).to include("Release `appcloud/0.1' already exists. Skipping upload.")
        end
      end

      context 'when NOT using the --skip-if-exists flag' do
        it 'tells the user and does exit as a failure' do
          output, exit_code = bosh_runner.run("upload release #{local_release_path}", {
            failure_expected: true,
            return_exit_code: true,
          })
          expect(output).to include('This release version has already been uploaded')
          expect(exit_code).to eq(1)
        end
      end
    end

    context 'when the release is remote' do
      let(:file_server) { Bosh::Spec::LocalFileServer.new(spec_asset(''), file_server_port, logger) }
      let(:file_server_port) { current_sandbox.get_named_port('releases-repo') }

      before { file_server.start }
      after { file_server.stop }

      let(:release_url) { file_server.http_url("valid_release.tgz") }

      before { bosh_runner.run("upload release #{release_url}") }

      it 'tells the user and does exit as a failure' do
        output, exit_code = bosh_runner.run("upload release #{release_url}", {
          failure_expected: true,
          return_exit_code: true,
        })
        expect(output).to include("Release `appcloud/0.1' already exists")
        expect(exit_code).to eq(1)
      end
    end
  end

  def with_changed_release
    new_file = File.join('src', 'bar', SecureRandom.uuid)
    begin
      FileUtils.touch(new_file)
      yield
    ensure
      FileUtils.rm_rf(new_file)
    end
  end
end