require 'unit_helper'
require 'osc_parser'

class OSCParseTester
  describe 'Testing the Parser' do

    before(:each) do
      @evaluator = OscParser.new
    end

    it 'tests for drop foreign key' do
      @result = @evaluator.parse_int("ALTER TABLE Orders DROP FOREIGN KEY
      fk_PerOrders /* ignore this */  , DROP FOREIGN KEY `a\n\nbc` -- , DROP FOREIGN KEY def")

      expect(@result[:stm]).to eq("ALTER TABLE Orders DROP FOREIGN KEY _fk_PerOrders\
 , DROP FOREIGN KEY `_a\n\nbc`")

    end

    it 'tests for bad alter' do
      expect{
        @evaluator.parse_int('ALTERTABLE Orders DROP FOREIGN KEY fk_PerOrder')
      }.to raise_error(ParseError)
    end

    it 'tests for alter table options' do
      @result = @evaluator.parse_int('ALTER ONLINE IGNORE TAbLE`myTaBle` ROW_FORMAT DYNAMIC, CHECKSUM = 0')
      expect(@result[:stm]).to eq('ALTER ONLINE IGNORE TAbLE `myTaBle` ROW_FORMAT DYNAMIC , CHECKSUM = 0')
    end

    it 'tests for run - short' do
      @result = @evaluator.parse_int('ALTER TABLE bogus DROP INDEX abc')
      expect(@result[:stm]).to eq('ALTER TABLE bogus DROP INDEX abc')
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for run - short multi 1' do
      @result = @evaluator.parse_int('ALTER TABLE bogus DROP INDEX abc, DROP INDEX def')
      expect(@result[:stm]).to eq('ALTER TABLE bogus DROP INDEX abc , DROP INDEX def')
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for run - short multi 2' do
      @result = @evaluator.parse_int("ALTER TABLE bogus DROP INDEX abc, MODIFY COLUMN x ENUM ('a', 'b', 'c')")
      expect(@result[:stm]).to eq("ALTER TABLE bogus DROP INDEX abc , MODIFY COLUMN x ENUM ('a','b','c')")
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for run - long 1' do
      @result = @evaluator.parse_int("ALTER TABLE bogus ENABLE KEYS, MODIFY COLUMN x ENUM ('a', 'b', 'c')")
      expect(@result[:stm]).to eq("ALTER TABLE bogus ENABLE KEYS , MODIFY COLUMN x ENUM ('a','b','c')")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for run - short 3' do
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a''def', 'b'     ,    'c''d'      ), MODIFY COLUMN y ENUM ('a', 'b', 'c')")
      expect(@result[:stm]).to eq("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a''def','b','c''d') , MODIFY COLUMN y ENUM ('a','b','c')")
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for double quote' do
      expect{
        @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM (\"def\", 'b'     , 'c'), MODIFY COLUMN y ENUM ('a', 'b', 'c')")
      }.to raise_error(ShiftError)
    end

    it 'tests for run - long 2' do
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a', 'b', 'c'), MODIFY COLUMN y INT")
      expect(@result[:stm]).to eq("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a','b','c') , MODIFY COLUMN y INT")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for enum - column not found' do
      checkers = {
        get_columns: lambda do |_|
          {
            'y' => {type: "enum('a','b')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      expect {
        @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a', 'b', 'c')")
      }.to raise_error(ShiftError)
    end

    it 'tests for enum - column found' do
      checkers = {
        get_columns: lambda do |_|
          {
            'y' => {type: "enum('a','b')"},
            'x' => {type: "enum('a','b')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a', 'b', 'c')")
      expect(@result[:stm]).to eq("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a','b','c')")
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for enum - some column not found' do
      checkers = {
        get_columns: lambda do |_|
          {
            'z' => {type: "enum('a','b')"},
            'x' => {type: "enum('a','b')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      expect {
        @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a', 'b', 'c'),
                                                MODIFY COLUMN y ENUM ('a', 'b', 'c')")
      }.to raise_error(ShiftError)
    end

    it 'tests for enum - all columns found' do
      checkers = {
        get_columns: lambda do |_|
          {
            'y' => {type: "enum('','b')"},
            'x' => {type: "enum('z','x')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('z', 'x', 'yyy'),
                                                        MODIFY COLUMN y ENUM ('', 'b', 'c')")
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for enum - enum long' do
      checkers = {
        get_columns: lambda do |_|
          {
            'y' => {type: "enum('a','b')"},
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN y ENUM ('a', 'd')")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for enum - enum long because some is long' do
      checkers = {
        get_columns: lambda do |_|
          {
            'y' => {type: "enum('a','b')"},
            'x' => {type: "enum('a','d')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a', 'd','e'), MODIFY COLUMN y ENUM ('a', 'd')")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for enum - enum long because some is long (swap)' do
      checkers = {
        get_columns: lambda do |_|
          {
            'y' => {type: "enum('a','b')"},
            'x' => {type: "enum('a','d')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN y ENUM ('a', 'd'), MODIFY COLUMN x ENUM ('a', 'd','e')")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for enum - enum long because of removing' do
      checkers = {
        get_columns: lambda do |_|
          {
            'y' => {type: "enum('a','b')"},
            'x' => {type: "enum('a','d')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM ('a')")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for enum - enum short because no byte changes' do
      checkers = {
        get_columns: lambda do |_|
          {
            'x' => {type: "enum('1','2')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      num_lst = (1..255).map { |c| "'#{c}'" }.join(',')
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM (#{num_lst})")
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for enum - enum short because byte changes' do
      checkers = {
        get_columns: lambda do |_|
          {
            'x' => {type: "enum('1','2')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      num_lst = (1..256).map { |c| "'#{c}'" }.join(',')
      @result = @evaluator.parse_int("ALTER TABLE bogus MODIFY COLUMN x ENUM (#{num_lst})")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for fk - append underscore' do
      @result = @evaluator.parse_int('ALTER TABLE bogus ENGINE=InnoDB , ROW_FORMAT=COMPRESSED, KEY_BLOCK_SIZE=4, CHECKSUM=1, DROP FOREIGN KEY fk1')
      expect(@result[:stm]).to eq('ALTER TABLE bogus ENGINE = InnoDB , ROW_FORMAT = COMPRESSED , KEY_BLOCK_SIZE = 4 , CHECKSUM = 1 , DROP FOREIGN KEY _fk1')
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for fk - remove underscore' do
      @result = @evaluator.parse_int('ALTER TABLE bogus ENGINE=InnoDB , ROW_FORMAT=COMPRESSED, KEY_BLOCK_SIZE=4, CHECKSUM=1, DROP FOREIGN KEY _fk3')
      expect(@result[:stm]).to eq('ALTER TABLE bogus ENGINE = InnoDB , ROW_FORMAT = COMPRESSED , KEY_BLOCK_SIZE = 4 , CHECKSUM = 1 , DROP FOREIGN KEY fk3')
      expect(@result[:run]).to eq(:long)
    end

    it 'tests alter union' do
      @result = @evaluator.parse_int('alter table abc MAX_ROWS = 1, UNION = (a, b, c), MIN_ROWS=0')
      expect(@result[:stm]).to eq('alter table abc MAX_ROWS = 1 , UNION = ( a , b , c ) , MIN_ROWS = 0')
    end

    it 'tests alter add columns' do
      @result = @evaluator.parse_int('alter table `add` add column abc DATE')
      expect(@result[:stm]).to eq('alter table `add` add column abc DATE')
    end

    it 'tests for bad keyword' do
      expect{
        @evaluator.parse_int('alter table select add column abc DATE')
      }.to raise_error(ParseError)
    end

    it 'tests from w3schools' do
      @result = @evaluator.parse_int('ALTER TABLE Persons
ADD DateOfBirth date')
      expect(@result[:stm]).to eq('ALTER TABLE Persons ADD DateOfBirth date')
    end

    it 'tests for discard tablespace' do
      @result = @evaluator.parse_int('ALTER TABLE Persons
DISCARD TABLESPACE')
      expect(@result[:stm]).to eq('ALTER TABLE Persons DISCARD TABLESPACE')
    end

    it 'tests for remove partitioning' do
      @result = @evaluator.parse_int('ALTER TABLE Persons
REMOVE PARTITIONING')
      expect(@result[:stm]).to eq('ALTER TABLE Persons REMOVE PARTITIONING')
    end

    it 'tests for normal op and remove partitioning' do
      @result = @evaluator.parse_int('ALTER TABLE Persons ENABLE KEYS
REMOVE PARTITIONING')
      expect(@result[:stm]).to eq('ALTER TABLE Persons ENABLE KEYS REMOVE PARTITIONING')
    end

    it 'tests from pending migration1' do
      @result = @evaluator.parse_int('ALTER TABLE transmission_entries ADD COLUMN live boolean DEFAULT NULL')
      expect(@result[:stm]).to eq('ALTER TABLE transmission_entries ADD COLUMN live boolean DEFAULT NULL')
    end

    it 'tests from failed migration1' do
      expect {
        @evaluator.parse_int('ALTER TABLE invoices DROP INDEX `merchant_invoice_number`, DROP INDEX `invoices_merchant_token_state_index`, CHANGE COLUMN merchant_token VARCHAR(255) NULL')
      }.to raise_error(ParseError)
    end

    it 'tests for bare alter table' do
      @result = @evaluator.parse_int('ALTER TABLE invoices')
      expect(@result[:stm]).to eq('ALTER TABLE invoices')
    end

    it 'tests for multidot' do
      @result = @evaluator.parse_int('DROP TABLE asd.dsa')
      expect(@result[:stm]).to eq('DROP TABLE asd.dsa')
      expect(@result[:run]).to eq(:short)
    end

    it 'tests for too many dot' do
      expect{
        @evaluator.parse_int('DROP TABLE asd.dsa.def')
      }.to raise_error(ParseError)
    end

    it 'tests for create table' do
      @result = @evaluator.parse_int("CREATE TABLE Persons (PersonID int)")

      expect(@result[:stm]).to eq("CREATE TABLE Persons ( PersonID int )")
      expect(@result[:run]).to eq(:short)
    end

    it 'tests that order not supported' do
      expect{
        @evaluator.parse_int('ALTER TABLE abc ORDER BY a, b, c')
      }.to raise_error(ShiftError)
    end

    it 'tests that partitioning is long run' do
      @result = @evaluator.parse_int('ALTER TABLE abc REMOVE PARTITIONING')
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for space at the beginning' do
      @result = @evaluator.parse_int('  ALTER TABLE abc REMOVE PARTITIONING')
      expect(@result[:stm]).to eq('ALTER TABLE abc REMOVE PARTITIONING')
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for create table' do
      @result = @evaluator.parse_int("CREATE TABLE Persons
(
PersonID int,
LastName varchar(255),
FirstName varchar(255),
Address varchar(255),
City varchar(255)
)")

      expect(@result[:stm]).to eq("CREATE TABLE Persons ( PersonID int , \
LastName varchar ( 255 ) , FirstName varchar ( 255 ) , \
Address varchar ( 255 ) , City varchar ( 255 ) )")
      expect(@result[:run]).to eq(:short)
    end

    it 'tests for create view' do
      @result = @evaluator.parse_int('CREATE VIEW asd AS def')
      expect(@result[:stm]).to eq('CREATE VIEW asd AS def')
      expect(@result[:run]).to eq(:short)
    end

    it 'tests for drop table' do
      @result = @evaluator.parse_int('DROP TABLE abc')
      expect(@result[:stm]).to eq('DROP TABLE abc')
      expect(@result[:run]).to eq(:short)
    end

    it 'tests for drop view' do
      @result = @evaluator.parse_int('DROP VIEW asd')
      expect(@result[:stm]).to eq('DROP VIEW asd')
      expect(@result[:run]).to eq(:short)
    end

    it 'tests for change ENUM with same name' do
      checkers = {
        get_columns: lambda do |_|
          {
            'dd' => {type: "enum('a')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE asd CHANGE COLUMN dd dd ENUM('a', 'b')")
      expect(@result[:stm]).to eq("ALTER TABLE asd CHANGE COLUMN dd dd ENUM ('a','b')")
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests for change ENUM with different name' do
      checkers = {
        get_columns: lambda do |_|
          {
            'dd' => {type: "enum('a')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE asd CHANGE COLUMN dd de ENUM('a', 'b')")
      expect(@result[:stm]).to eq("ALTER TABLE asd CHANGE COLUMN dd de ENUM ('a','b')")
      expect(@result[:run]).to eq(:maybenocheckalter)
    end

    it 'tests for change non-ENUM column with same name' do
      checkers = {
        get_columns: lambda do |_|
          {
            'dd' => {type: "enum('a')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE asd CHANGE COLUMN dd dd int(11)")
      expect(@result[:stm]).to eq("ALTER TABLE asd CHANGE COLUMN dd dd int ( 11 )")
      expect(@result[:run]).to eq(:long)
    end

    it 'tests for change non-ENUM column with different name' do
      checkers = {
        get_columns: lambda do |_|
          {
            'dd' => {type: "int(11)"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int("ALTER TABLE asd CHANGE COLUMN dd de int(11)")
      expect(@result[:stm]).to eq("ALTER TABLE asd CHANGE COLUMN dd de int ( 11 )")
      expect(@result[:run]).to eq(:maybenocheckalter)
    end

    it 'tests for change column not found' do
      checkers = {
        get_columns: lambda do |_|
          {
            'de' => {type: "enum('a')"}
          }
        end
      }
      @evaluator.merge_checkers! checkers
      expect{
        puts @evaluator.parse_int("ALTER TABLE asd CHANGE COLUMN dd de ENUM('a', 'b')")
      }.to raise_error(ShiftError)

    end

    it 'tests that an osc will always be longrun for alters that do not avoid temporal upgrade' do
      checkers = {
        avoid_temporal_upgrade?: lambda { false }
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int('ALTER TABLE abc')
      expect(@result[:run]).to eq(:long)
    end

    it 'tests that an osc will be maybeshort for alters that avoid temporal upgrade' do
      checkers = {
        avoid_temporal_upgrade?: lambda { true }
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int('ALTER TABLE abc')
      expect(@result[:run]).to eq(:maybeshort)
    end

    it 'tests that an osc will always be short for non-alter' do
      checkers = {
        avoid_temporal_upgrade?: lambda { false }
      }
      @evaluator.merge_checkers! checkers
      @result = @evaluator.parse_int('DROP TABLE abc')
      expect(@result[:run]).to eq(:short)
    end
  end
end
