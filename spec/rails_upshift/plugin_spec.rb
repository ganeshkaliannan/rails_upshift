require 'spec_helper'

RSpec.describe RailsUpshift::Plugin do
  describe 'initialization' do
    it 'initializes with name and description' do
      plugin = described_class.new('test_plugin', 'A test plugin')
      
      expect(plugin.name).to eq('test_plugin')
      expect(plugin.description).to eq('A test plugin')
      expect(plugin.patterns).to be_empty
      expect(plugin.fixes).to be_empty
    end
  end
  
  describe '#register_pattern' do
    let(:plugin) { described_class.new('test_plugin', 'A test plugin') }
    
    it 'registers a pattern with required parameters' do
      plugin.register_pattern(
        pattern: /Time\.now/,
        message: 'Use Time.current instead',
        file_pattern: '**/*.rb'
      )
      
      expect(plugin.patterns.size).to eq(1)
      expect(plugin.patterns.first[:pattern]).to eq(/Time\.now/)
      expect(plugin.patterns.first[:message]).to eq('Use Time.current instead')
      expect(plugin.patterns.first[:file_pattern]).to eq('**/*.rb')
      expect(plugin.patterns.first[:version_constraint]).to be_nil
    end
    
    it 'registers a pattern with version constraint' do
      plugin.register_pattern(
        pattern: /update_attributes/,
        message: 'Use update instead',
        file_pattern: 'app/models/**/*.rb',
        version_constraint: '>= 6.0.0'
      )
      
      expect(plugin.patterns.size).to eq(1)
      expect(plugin.patterns.first[:pattern]).to eq(/update_attributes/)
      expect(plugin.patterns.first[:message]).to eq('Use update instead')
      expect(plugin.patterns.first[:file_pattern]).to eq('app/models/**/*.rb')
      expect(plugin.patterns.first[:version_constraint]).to eq('>= 6.0.0')
    end
    
    it 'registers multiple patterns' do
      plugin.register_pattern(
        pattern: /Time\.now/,
        message: 'Use Time.current instead',
        file_pattern: '**/*.rb'
      )
      
      plugin.register_pattern(
        pattern: /Date\.today/,
        message: 'Use Time.current.to_date instead',
        file_pattern: '**/*.rb'
      )
      
      expect(plugin.patterns.size).to eq(2)
    end
  end
  
  describe '#register_fix' do
    let(:plugin) { described_class.new('test_plugin', 'A test plugin') }
    
    it 'registers a string replacement fix' do
      plugin.register_fix(
        pattern: /Time\.now/,
        replacement: 'Time.current'
      )
      
      expect(plugin.fixes.size).to eq(1)
      expect(plugin.fixes['Time\.now'][:replacement]).to eq('Time.current')
      expect(plugin.fixes['Time\.now'][:safe]).to be true
    end
    
    it 'registers a proc replacement fix' do
      replacement_proc = ->(match) { "Time.current # was: #{match}" }
      
      plugin.register_fix(
        pattern: /Time\.now/,
        replacement: replacement_proc
      )
      
      expect(plugin.fixes.size).to eq(1)
      expect(plugin.fixes['Time\.now'][:replacement]).to be_a(Proc)
      expect(plugin.fixes['Time\.now'][:safe]).to be true
    end
    
    it 'registers an unsafe fix' do
      plugin.register_fix(
        pattern: /update_attributes/,
        replacement: 'update',
        safe: false
      )
      
      expect(plugin.fixes.size).to eq(1)
      expect(plugin.fixes['update_attributes'][:replacement]).to eq('update')
      expect(plugin.fixes['update_attributes'][:safe]).to be false
    end
  end
  
  describe '#apply_to_analyzer' do
    let(:plugin) { described_class.new('test_plugin', 'A test plugin') }
    let(:analyzer) { instance_double('RailsUpshift::Analyzer', target_version: '6.0.0', scan_for_pattern: nil) }
    
    before do
      plugin.register_pattern(
        pattern: /Time\.now/,
        message: 'Use Time.current instead',
        file_pattern: '**/*.rb'
      )
      
      plugin.register_pattern(
        pattern: /update_attributes/,
        message: 'Use update instead',
        file_pattern: 'app/models/**/*.rb',
        version_constraint: '>= 6.0.0'
      )
      
      plugin.register_pattern(
        pattern: /find_by_id/,
        message: 'Use find_by(id: ...) instead',
        file_pattern: 'app/models/**/*.rb',
        version_constraint: '< 6.0.0'
      )
    end
    
    it 'applies matching patterns to the analyzer' do
      expect(analyzer).to receive(:scan_for_pattern).with(
        pattern: /Time\.now/,
        message: 'Use Time.current instead',
        file_pattern: '**/*.rb'
      )
      
      expect(analyzer).to receive(:scan_for_pattern).with(
        pattern: /update_attributes/,
        message: 'Use update instead',
        file_pattern: 'app/models/**/*.rb'
      )
      
      # This pattern should be skipped due to version constraint
      expect(analyzer).not_to receive(:scan_for_pattern).with(
        pattern: /find_by_id/,
        message: 'Use find_by(id: ...) instead',
        file_pattern: 'app/models/**/*.rb'
      )
      
      plugin.apply_to_analyzer(analyzer)
    end
  end
  
  describe '#apply_to_upgrader' do
    let(:plugin) { described_class.new('test_plugin', 'A test plugin') }
    let(:upgrader) { instance_double('RailsUpshift::Upgrader', register_fix: nil) }
    
    before do
      plugin.register_fix(
        pattern: /Time\.now/,
        replacement: 'Time.current'
      )
      
      plugin.register_fix(
        pattern: /update_attributes/,
        replacement: 'update',
        safe: false
      )
    end
    
    it 'applies fixes to the upgrader' do
      expect(upgrader).to receive(:register_fix).with(
        pattern: /Time\.now/,
        replacement: 'Time.current',
        safe: true
      )
      
      expect(upgrader).to receive(:register_fix).with(
        pattern: /update_attributes/,
        replacement: 'update',
        safe: false
      )
      
      plugin.apply_to_upgrader(upgrader)
    end
  end
  
  describe '#version_matches?' do
    let(:plugin) { described_class.new('test_plugin', 'A test plugin') }
    
    it 'matches >= constraint correctly' do
      expect(plugin.send(:version_matches?, '6.0.0', '>= 6.0.0')).to be true
      expect(plugin.send(:version_matches?, '6.1.0', '>= 6.0.0')).to be true
      expect(plugin.send(:version_matches?, '5.2.0', '>= 6.0.0')).to be false
    end
    
    it 'matches > constraint correctly' do
      expect(plugin.send(:version_matches?, '6.0.0', '> 6.0.0')).to be false
      expect(plugin.send(:version_matches?, '6.1.0', '> 6.0.0')).to be true
      expect(plugin.send(:version_matches?, '5.2.0', '> 6.0.0')).to be false
    end
    
    it 'matches <= constraint correctly' do
      expect(plugin.send(:version_matches?, '6.0.0', '<= 6.0.0')).to be true
      expect(plugin.send(:version_matches?, '6.1.0', '<= 6.0.0')).to be false
      expect(plugin.send(:version_matches?, '5.2.0', '<= 6.0.0')).to be true
    end
    
    it 'matches < constraint correctly' do
      expect(plugin.send(:version_matches?, '6.0.0', '< 6.0.0')).to be false
      expect(plugin.send(:version_matches?, '6.1.0', '< 6.0.0')).to be false
      expect(plugin.send(:version_matches?, '5.2.0', '< 6.0.0')).to be true
    end
    
    it 'matches == constraint correctly' do
      expect(plugin.send(:version_matches?, '6.0.0', '== 6.0.0')).to be true
      expect(plugin.send(:version_matches?, '6.1.0', '== 6.0.0')).to be false
      expect(plugin.send(:version_matches?, '5.2.0', '== 6.0.0')).to be false
    end
    
    it 'matches ~> constraint correctly' do
      expect(plugin.send(:version_matches?, '6.0.0', '~> 6.0.0')).to be true
      expect(plugin.send(:version_matches?, '6.0.9', '~> 6.0.0')).to be true
      expect(plugin.send(:version_matches?, '6.1.0', '~> 6.0.0')).to be false
      expect(plugin.send(:version_matches?, '5.2.0', '~> 6.0.0')).to be false
    end
    
    it 'returns false for invalid constraints' do
      expect(plugin.send(:version_matches?, '6.0.0', 'invalid 6.0.0')).to be false
    end
  end
end

RSpec.describe RailsUpshift::PluginManager do
  describe '.instance' do
    it 'returns a singleton instance' do
      instance1 = described_class.instance
      instance2 = described_class.instance
      
      expect(instance1).to be_a(described_class)
      expect(instance1).to eq(instance2)
    end
  end
  
  describe '#register' do
    let(:manager) { described_class.new }
    let(:plugin) { RailsUpshift::Plugin.new('test_plugin', 'A test plugin') }
    
    it 'registers a plugin' do
      manager.register(plugin)
      
      expect(manager.get('test_plugin')).to eq(plugin)
    end
    
    it 'overwrites a plugin with the same name' do
      plugin1 = RailsUpshift::Plugin.new('test_plugin', 'First plugin')
      plugin2 = RailsUpshift::Plugin.new('test_plugin', 'Second plugin')
      
      manager.register(plugin1)
      manager.register(plugin2)
      
      expect(manager.get('test_plugin')).to eq(plugin2)
    end
  end
  
  describe '#get' do
    let(:manager) { described_class.new }
    let(:plugin) { RailsUpshift::Plugin.new('test_plugin', 'A test plugin') }
    
    before do
      manager.register(plugin)
    end
    
    it 'returns a registered plugin by name' do
      expect(manager.get('test_plugin')).to eq(plugin)
    end
    
    it 'returns nil for an unregistered plugin' do
      expect(manager.get('unknown_plugin')).to be_nil
    end
  end
  
  describe '#all' do
    let(:manager) { described_class.new }
    
    it 'returns all registered plugins' do
      plugin1 = RailsUpshift::Plugin.new('plugin1', 'First plugin')
      plugin2 = RailsUpshift::Plugin.new('plugin2', 'Second plugin')
      
      manager.register(plugin1)
      manager.register(plugin2)
      
      expect(manager.all).to contain_exactly(plugin1, plugin2)
    end
    
    it 'returns an empty array when no plugins are registered' do
      expect(manager.all).to be_empty
    end
  end
  
  describe '#apply_to_analyzer' do
    let(:manager) { described_class.new }
    let(:analyzer) { instance_double('RailsUpshift::Analyzer') }
    
    it 'applies all registered plugins to the analyzer' do
      plugin1 = instance_double('RailsUpshift::Plugin')
      plugin2 = instance_double('RailsUpshift::Plugin')
      
      expect(plugin1).to receive(:apply_to_analyzer).with(analyzer)
      expect(plugin2).to receive(:apply_to_analyzer).with(analyzer)
      
      manager.instance_variable_set(:@plugins, {
        'plugin1' => plugin1,
        'plugin2' => plugin2
      })
      
      manager.apply_to_analyzer(analyzer)
    end
  end
  
  describe '#apply_to_upgrader' do
    let(:manager) { described_class.new }
    let(:upgrader) { instance_double('RailsUpshift::Upgrader') }
    
    it 'applies all registered plugins to the upgrader' do
      plugin1 = instance_double('RailsUpshift::Plugin')
      plugin2 = instance_double('RailsUpshift::Plugin')
      
      expect(plugin1).to receive(:apply_to_upgrader).with(upgrader)
      expect(plugin2).to receive(:apply_to_upgrader).with(upgrader)
      
      manager.instance_variable_set(:@plugins, {
        'plugin1' => plugin1,
        'plugin2' => plugin2
      })
      
      manager.apply_to_upgrader(upgrader)
    end
  end
end
