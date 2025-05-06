require 'spec_helper'
require 'fileutils'

RSpec.describe "RailsUpshift Migration Version Updates" do
  let(:temp_dir) { File.join(Dir.tmpdir, "rails_upshift_test_#{Time.now.to_i}") }
  
  before do
    FileUtils.mkdir_p(temp_dir)
    FileUtils.mkdir_p(File.join(temp_dir, 'db', 'migrate'))
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  it 'updates Rails 4.x style migrations to include the target Rails version' do
    # Create a Rails 4.x style migration file
    migration_path = File.join(temp_dir, 'db', 'migrate', '20200101000000_create_users.rb')
    File.write(migration_path, <<~RUBY)
      class CreateUsers < ActiveRecord::Migration
        def change
          create_table :users do |t|
            t.string :name
            t.string :email
            t.timestamps
          end
        end
      end
    RUBY
    
    # Enable update_configs option
    options = { 
      update_configs: true,  # This will trigger update_migration_versions by default
      target_version: '5.2.0',
      verbose: true,
      dry_run: false
    }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, [], options)
    result = upgrader.upgrade
    
    # Check if the file was fixed
    expect(result[:fixed_files]).to include('db/migrate/20200101000000_create_users.rb')
    
    # Check content
    content = File.read(migration_path)
    expect(content).to include('class CreateUsers < ActiveRecord::Migration[5.2]')
    expect(content).to include('t.timestamps precision: 6')
  end
  
  it 'updates existing versioned migrations to the target Rails version' do
    # Create a migration file with an existing version
    migration_path = File.join(temp_dir, 'db', 'migrate', '20200101000001_create_posts.rb')
    File.write(migration_path, <<~RUBY)
      class CreatePosts < ActiveRecord::Migration[5.0]
        def change
          create_table :posts do |t|
            t.string :title
            t.text :content
            t.references :user
            t.timestamps
          end
        end
      end
    RUBY
    
    # Enable update_configs option
    options = { 
      update_configs: true,  # This will trigger update_migration_versions by default
      target_version: '5.2.0',
      verbose: true,
      dry_run: false
    }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, [], options)
    result = upgrader.upgrade
    
    # Check if the file was fixed
    expect(result[:fixed_files]).to include('db/migrate/20200101000001_create_posts.rb')
    
    # Check content
    content = File.read(migration_path)
    expect(content).to include('class CreatePosts < ActiveRecord::Migration[5.2]')
    expect(content).to include('t.references :user, foreign_key: true')
    expect(content).to include('t.timestamps precision: 6')
  end
  
  it 'handles multiple migration files correctly' do
    # Create multiple migration files
    migration1_path = File.join(temp_dir, 'db', 'migrate', '20200101000000_create_users.rb')
    File.write(migration1_path, <<~RUBY)
      class CreateUsers < ActiveRecord::Migration
        def change
          create_table :users do |t|
            t.string :name
            t.string :email
            t.timestamps
          end
        end
      end
    RUBY
    
    migration2_path = File.join(temp_dir, 'db', 'migrate', '20200101000001_create_posts.rb')
    File.write(migration2_path, <<~RUBY)
      class CreatePosts < ActiveRecord::Migration[5.0]
        def change
          create_table :posts do |t|
            t.string :title
            t.text :content
            t.references :user
            t.timestamps
          end
        end
      end
    RUBY
    
    migration3_path = File.join(temp_dir, 'db', 'migrate', '20200101000002_create_comments.rb')
    File.write(migration3_path, <<~RUBY)
      class CreateComments < ActiveRecord::Migration[5.1]
        def change
          create_table :comments do |t|
            t.text :body
            t.references :post
            t.references :user
            t.timestamps
          end
        end
      end
    RUBY
    
    # Enable update_configs option
    options = { 
      update_configs: true,  # This will trigger update_migration_versions by default
      target_version: '5.2.0',
      verbose: true,
      dry_run: false
    }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, [], options)
    result = upgrader.upgrade
    
    # Check if all files were fixed
    expect(result[:fixed_files]).to include('db/migrate/20200101000000_create_users.rb')
    expect(result[:fixed_files]).to include('db/migrate/20200101000001_create_posts.rb')
    expect(result[:fixed_files]).to include('db/migrate/20200101000002_create_comments.rb')
    
    # Check content of each file
    content1 = File.read(migration1_path)
    expect(content1).to include('class CreateUsers < ActiveRecord::Migration[5.2]')
    expect(content1).to include('t.timestamps precision: 6')
    
    content2 = File.read(migration2_path)
    expect(content2).to include('class CreatePosts < ActiveRecord::Migration[5.2]')
    expect(content2).to include('t.references :user, foreign_key: true')
    expect(content2).to include('t.timestamps precision: 6')
    
    content3 = File.read(migration3_path)
    expect(content3).to include('class CreateComments < ActiveRecord::Migration[5.2]')
    expect(content3).to include('t.references :post, foreign_key: true')
    expect(content3).to include('t.references :user, foreign_key: true')
    expect(content3).to include('t.timestamps precision: 6')
  end
  
  it 'applies Rails 6.0+ specific updates to migrations' do
    # Create a migration file with Rails 5.0 style
    migration_path = File.join(temp_dir, 'db', 'migrate', '20200101000003_create_products.rb')
    File.write(migration_path, <<~RUBY)
      class CreateProducts < ActiveRecord::Migration[5.0]
        def change
          create_table :products do |t|
            t.string :name
            t.string :sku
            t.decimal :price, precision: 10, scale: 2
            t.jsonb :metadata
            t.belongs_to :category
            t.timestamps
          end
        end
      end
    RUBY
    
    # Enable update_configs option with Rails 6.0 target
    options = { 
      update_configs: true,
      target_version: '6.0.0',
      verbose: true,
      dry_run: false
    }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, [], options)
    result = upgrader.upgrade
    
    # Check if the file was fixed
    expect(result[:fixed_files]).to include('db/migrate/20200101000003_create_products.rb')
    
    # Check content
    content = File.read(migration_path)
    expect(content).to include('class CreateProducts < ActiveRecord::Migration[6.0]')
    expect(content).to include('t.string :name, null: false')
    expect(content).to include('t.string :sku, null: false')
    expect(content).to include('t.jsonb :metadata, default: {}')
    expect(content).to include('t.belongs_to :category, foreign_key: true')
    expect(content).to include('t.timestamps precision: 6')
  end
  
  it 'applies Rails 7.0+ specific updates to migrations' do
    # Create a migration file with Rails 6.0 style
    migration_path = File.join(temp_dir, 'db', 'migrate', '20200101000004_create_orders.rb')
    File.write(migration_path, <<~RUBY)
      class CreateOrders < ActiveRecord::Migration[6.0]
        def change
          create_table :orders do |t|
            t.string :order_number, null: false
            t.decimal :total, precision: 10, scale: 2
            t.references :user, foreign_key: true
            t.timestamps precision: 6
          end
        end
      end
    RUBY
    
    # Enable update_configs option with Rails 7.0 target
    options = { 
      update_configs: true,
      target_version: '7.0.0',
      verbose: true,
      dry_run: false
    }
    
    # Create upgrader and run upgrade
    upgrader = RailsUpshift::Upgrader.new(temp_dir, [], options)
    result = upgrader.upgrade
    
    # Check if the file was fixed
    expect(result[:fixed_files]).to include('db/migrate/20200101000004_create_orders.rb')
    
    # Check content
    content = File.read(migration_path)
    expect(content).to include('class CreateOrders < ActiveRecord::Migration[7.0]')
    expect(content).to include('create_table :orders, if_not_exists: true')
    expect(content).to include('t.timestamps precision: 6')
  end
end
