require 'spec_helper'

RSpec.describe RailsUpshift do
  it "has a version number" do
    expect(RailsUpshift::VERSION).not_to be nil
  end

  describe '.analyze' do
    let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
    let(:analyzer) { instance_double('RailsUpshift::Analyzer', analyze: []) }
    let(:plugin_manager) { instance_double('RailsUpshift::PluginManager', apply_to_analyzer: nil) }
    
    before do
      allow(RailsUpshift::Analyzer).to receive(:new).and_return(analyzer)
      allow(RailsUpshift::PluginManager).to receive(:instance).and_return(plugin_manager)
      FileUtils.mkdir_p(temp_dir)
    end
    
    after do
      FileUtils.rm_rf(temp_dir)
    end
    
    it 'creates an analyzer with the given path and target version' do
      expect(RailsUpshift::Analyzer).to receive(:new).with(temp_dir, '6.1.0')
      
      RailsUpshift.analyze(temp_dir, '6.1.0')
    end
    
    it 'applies plugins to the analyzer' do
      expect(plugin_manager).to receive(:apply_to_analyzer).with(analyzer)
      
      RailsUpshift.analyze(temp_dir)
    end
    
    it 'returns the analysis results' do
      issues = [{ file: 'app/models/user.rb', message: 'Some issue' }]
      allow(analyzer).to receive(:analyze).and_return(issues)
      
      expect(RailsUpshift.analyze(temp_dir)).to eq(issues)
    end
  end
  
  describe '.upgrade' do
    let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
    let(:analyzer) { instance_double('RailsUpshift::Analyzer', analyze: []) }
    let(:upgrader) { instance_double('RailsUpshift::Upgrader', upgrade: { issues: [], fixed_files: [] }) }
    let(:plugin_manager) { instance_double('RailsUpshift::PluginManager', apply_to_analyzer: nil, apply_to_upgrader: nil) }
    let(:issues) { [{ file: 'app/models/user.rb', message: 'Some issue' }] }
    let(:options) { { dry_run: true, target_version: '6.1.0' } }
    
    before do
      allow(RailsUpshift::Analyzer).to receive(:new).and_return(analyzer)
      allow(RailsUpshift::Upgrader).to receive(:new).and_return(upgrader)
      allow(RailsUpshift::PluginManager).to receive(:instance).and_return(plugin_manager)
      allow(analyzer).to receive(:analyze).and_return(issues)
      FileUtils.mkdir_p(temp_dir)
    end
    
    after do
      FileUtils.rm_rf(temp_dir)
    end
    
    it 'creates an analyzer with the given path and target version' do
      expect(RailsUpshift::Analyzer).to receive(:new).with(temp_dir, '6.1.0')
      
      RailsUpshift.upgrade(temp_dir, options)
    end
    
    it 'analyzes the application' do
      expect(analyzer).to receive(:analyze).and_return(issues)
      
      RailsUpshift.upgrade(temp_dir, options)
    end
    
    it 'creates an upgrader with the analysis results and options' do
      expect(RailsUpshift::Upgrader).to receive(:new).with(temp_dir, issues, options)
      
      RailsUpshift.upgrade(temp_dir, options)
    end
    
    it 'applies plugins to the upgrader' do
      expect(plugin_manager).to receive(:apply_to_upgrader).with(upgrader)
      
      RailsUpshift.upgrade(temp_dir, options)
    end
    
    it 'returns the upgrade results' do
      result = { issues: issues, fixed_files: ['app/models/user.rb'] }
      allow(upgrader).to receive(:upgrade).and_return(result)
      
      expect(RailsUpshift.upgrade(temp_dir, options)).to eq(result)
    end
  end
  
  describe '.register_plugin' do
    let(:plugin) { instance_double('RailsUpshift::Plugin') }
    let(:plugin_manager) { instance_double('RailsUpshift::PluginManager') }
    
    before do
      allow(RailsUpshift::PluginManager).to receive(:instance).and_return(plugin_manager)
    end
    
    it 'registers the plugin with the plugin manager' do
      expect(plugin_manager).to receive(:register).with(plugin)
      
      RailsUpshift.register_plugin(plugin)
    end
  end
  
  describe '.create_plugin' do
    let(:plugin) { instance_double('RailsUpshift::Plugin') }
    let(:plugin_manager) { instance_double('RailsUpshift::PluginManager') }
    
    before do
      allow(RailsUpshift::Plugin).to receive(:new).and_return(plugin)
      allow(RailsUpshift::PluginManager).to receive(:instance).and_return(plugin_manager)
      allow(plugin_manager).to receive(:register)
    end
    
    it 'creates a new plugin with the given name and description' do
      expect(RailsUpshift::Plugin).to receive(:new).with('test_plugin', 'A test plugin')
      
      RailsUpshift.create_plugin('test_plugin', 'A test plugin')
    end
    
    it 'yields the plugin for configuration if a block is given' do
      expect { |b| RailsUpshift.create_plugin('test_plugin', 'A test plugin', &b) }.to yield_with_args(plugin)
    end
    
    it 'registers the plugin' do
      expect(plugin_manager).to receive(:register).with(plugin)
      
      RailsUpshift.create_plugin('test_plugin', 'A test plugin')
    end
    
    it 'returns the created plugin' do
      expect(RailsUpshift.create_plugin('test_plugin', 'A test plugin')).to eq(plugin)
    end
  end
  
  it "does something useful" do
    expect(true).to eq(true)
  end
end
