require "yaml"

require "./entry"

class DirEntry < Entry
  include YAML::Serializable

  getter dir_path : String

  @[YAML::Field(ignore: true)]
  @sorted_files : Array(String)?

  @signature : String

  def initialize(@dir_path, @book)
    storage = Storage.default
    @encoded_path = URI.encode @dir_path
    @title = File.basename @dir_path
    @encoded_title = URI.encode @title

    unless File.readable? @dir_path
      @err_msg = "Directory #{@dir_path} is not readable."
      Logger.warn "#{@err_msg} Please make sure the " \
                  "file permission is configured correctly."
      return
    end

    unless DirEntry.validate_directory_entry @dir_path
      @err_msg = "Directory #{@dir_path} is not valid directory entry."
      Logger.warn "#{@err_msg} Please make sure the " \
                  "directory has valid images."
      return
    end

    size_sum = 0
    sorted_files.each do |file_path|
      size_sum += File.size file_path
    end
    @size = size_sum.humanize_bytes

    @signature = Dir.directory_entry_signature @dir_path
    id = storage.get_entry_id @dir_path, @signature
    if id.nil?
      id = random_str
      storage.insert_entry_id({
        path:      @dir_path,
        id:        id,
        signature: @signature,
      })
    end
    @id = id

    @mtime = sorted_files.map do |file_path|
      File.info(file_path).modification_time
    end.max
    @pages = sorted_files.size
  end

  def path : String
    @dir_path
  end

  def createtime : Time
    ctime @dir_path
  end

  def read_page(page_num)
    img = nil
    begin
      files = sorted_files
      file_path = files[page_num - 1]
      data = File.read(file_path).to_slice
      if data
        img = Image.new data, MIME.from_filename(file_path),
          File.basename(file_path), data.size
      end
    rescue e
      Logger.warn "Unable to read page #{page_num} of #{@dir_path}. Error: #{e}"
    end
    img
  end

  def page_dimensions
    sizes = [] of Hash(String, Int32)
    sorted_files.each_with_index do |path, i|
      data = File.read(path).to_slice
      begin
        data.not_nil!
        size = ImageSize.get data
        sizes << {
          "width"  => size.width,
          "height" => size.height,
        }
      rescue e
        Logger.warn "Failed to read page #{i} of entry #{@dir_path}. #{e}"
        sizes << {"width" => 1000_i32, "height" => 1000_i32}
      end
    end
    sizes
  end

  def examine : Bool
    existence = File.exists? @dir_path
    return false unless existence
    files = DirEntry.get_valid_files @dir_path
    signature = Dir.directory_entry_signature @dir_path
    existence = files.size > 0 && @signature == signature
    @sorted_files = nil unless existence

    # For more efficient, update a directory entry with new property
    # and return true like Title.examine
    existence
  end

  def sorted_files
    cached_sorted_files = @sorted_files
    return cached_sorted_files if cached_sorted_files
    @sorted_files = DirEntry.get_valid_files_sorted @dir_path
    @sorted_files.not_nil!
  end

  def self.validate_directory_entry(dir_path)
    files = DirEntry.get_valid_files dir_path
    files.size > 0
  end

  def self.get_valid_files(dir_path)
    files = [] of String
    Dir.entries(dir_path).each do |fn|
      next if fn.starts_with? "."
      path = File.join dir_path, fn
      next unless is_supported_image_file path
      next if File.directory? path
      next unless File.readable? path
      files << path
    end
    files
  end

  def self.get_valid_files_sorted(dir_path)
    files = DirEntry.get_valid_files dir_path
    files.sort! { |a, b| compare_numerically a, b }
  end
end
