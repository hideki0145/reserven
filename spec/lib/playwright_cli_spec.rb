require 'rails_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Playwright CLI wrapper' do
  around do |example|
    Dir.mktmpdir('reserven-playwright-cli-') do |directory|
      @directory = Pathname.new(directory)
      FileUtils.mkdir_p(@directory.join('bin'))
      FileUtils.mkdir_p(@directory.join('config'))
      FileUtils.cp(Rails.root.join('bin/playwright'), @directory.join('bin/playwright'))
      @directory.join('config/boot.rb').write('')
      example.run
    end
  end

  def run_wrapper(*arguments)
    Open3.capture3(RbConfig.ruby, @directory.join('bin/playwright').to_s, *arguments)
  end

  def install_cli(version)
    FileUtils.mkdir_p(@directory.join('node_modules/.bin'))
    FileUtils.mkdir_p(@directory.join('node_modules/playwright'))
    @directory.join('node_modules/playwright/package.json').write(JSON.generate(version: version))
    cli = @directory.join('node_modules/.bin/playwright')
    cli.write("#!/usr/bin/env ruby\nputs ARGV.join(' ')\n")
    cli.chmod(0o755)
  end

  it 'explains how to install a missing CLI' do
    _, stderr, status = run_wrapper('--version')
    expect(status).not_to be_success
    expect(stderr).to include('Run npm ci first')
  end

  it 'rejects a CLI incompatible with the Ruby client' do
    install_cli('0.0.0')
    _, stderr, status = run_wrapper('--version')
    expect(status).not_to be_success
    expect(stderr).to include('Playwright version mismatch')
  end

  it 'passes arguments to the compatible local CLI' do
    install_cli(Playwright::COMPATIBLE_PLAYWRIGHT_VERSION.strip)
    stdout, stderr, status = run_wrapper('install', 'chromium')
    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout.strip).to eq('install chromium')
  end
end
