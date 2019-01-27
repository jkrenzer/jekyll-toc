# frozen_string_literal: true

module Jekyll
  module TableOfContents
    # Parse html contents and generate table of contents
    class Parser
      NO_TOC_CLASS_NAME = 'no_toc'
      PUNCTUATION_REGEXP = /[^\p{Word}\- ]/u

      DEFAULT_CONFIG = {
        'no_toc_section_class' => 'no_toc_section',
        'min_level' => 1,
        'max_level' => 6,
        'list_class' => 'section-nav',
        'sublist_class' => '',
        'item_class' => 'toc-entry',
        'item_prefix' => 'toc-',
	'link_class' => ''
      }.freeze

      def initialize(html, options = {})
        @doc = Nokogiri::HTML::DocumentFragment.parse(html)
        options = generate_option_hash(options)
        @toc_levels = options['min_level']..options['max_level']
        @no_toc_section_class = options['no_toc_section_class']
        @list_class = options['list_class']
        @sublist_class = options['sublist_class']
        @item_class = options['item_class']
	if @item_class.is_a?(Array)
  	  @item_class.at(1) ||= @sublist_class
	elsif @item_class.is_a?(Hash)
	  @item_class.at(1) ||= @sublist_class
	else
	  @item_class = [ @item_class , @sublist_class]
	end
        @item_prefix = options['item_prefix']
	@link_class = options['link_class']
        @entries = parse_content
      end

      def toc
        build_toc + inject_anchors_into_html
      end

      def build_toc
        %(<ul class="#{@list_class}">\n#{build_toc_list(@entries)}</ul>)
      end

      def inject_anchors_into_html
        @entries.each do |entry|
          entry[:content_node].add_previous_sibling(
            %(<a id="#{entry[:id]}#{entry[:uniq]}" class="anchor" href="##{entry[:id]}#{entry[:uniq]}" aria-hidden="true"><span class="octicon octicon-link"></span></a>)
          )
        end

        @doc.inner_html
      end

      private

      # parse logic is from html-pipeline toc_filter
      # https://github.com/jch/html-pipeline/blob/v1.1.0/lib/html/pipeline/toc_filter.rb
      def parse_content
        headers = Hash.new(0)

        (@doc.css(toc_headings) - @doc.css(toc_headings_in_no_toc_section))
          .reject { |n| n.classes.include?(NO_TOC_CLASS_NAME) }
          .inject([]) do |entries, node|
          text = node.text
          id = node.attribute('id') || text
               .downcase
               .gsub(PUNCTUATION_REGEXP, '') # remove punctuation
               .tr(' ', '-') # replace spaces with dash

          uniq = headers[id].positive? ? "-#{headers[id]}" : ''
          headers[id] += 1
          header_content = node.children.first
          next entries unless header_content

          entries << {
            id: id,
            uniq: uniq,
            text: CGI.escapeHTML(text),
            node_name: node.name,
            content_node: header_content,
            h_num: node.name.delete('h').to_i
          }
        end
      end

      # Returns the list items for entries
      def build_toc_list(entries, level=0)
        i = 0
        toc_list = +''
        min_h_num = entries.map { |e| e[:h_num] }.min
	# Enforce Level >= 0
	if level < 0
	  level = 0
	end

        while i < entries.count
          entry = entries[i]
          if entry[:h_num] == min_h_num
            # If the current entry should not be indented in the list, add the entry to the list
            toc_list << %(<li class="#{lvl_opt_val(@item_class, level, DEFAULT_CONFIG['item_class'])} #{@item_prefix}#{entry[:node_name]}"><a #{lvl_attr(@link_class, level, DEFAULT_CONFIG['link_class'])}href="##{entry[:id]}#{entry[:uniq]}">#{entry[:text]}</a>)
            # If the next entry should be indented in the list, generate a sublist
            next_i = i + 1
            if next_i < entries.count && entries[next_i][:h_num] > min_h_num
              nest_entries = get_nest_entries(entries[next_i, entries.count], min_h_num)
              toc_list << %(\n<ul #{lvl_attr(@list_class, level + 1, DEFAULT_CONFIG['sublist_class'])}>\n#{build_toc_list(nest_entries, level + 1)}</ul>\n)
              i += nest_entries.count
            end
            # Add the closing tag for the current entry in the list
            toc_list << %(</li>\n)
          elsif entry[:h_num] > min_h_num
            # If the current entry should be indented in the list, generate a sublist
            nest_entries = get_nest_entries(entries[i, entries.count], min_h_num)
            toc_list << build_toc_list(nest_entries)
            i += nest_entries.count - 1
          end
          i += 1
        end

        toc_list
      end

      # Returns the entries in a nested list
      # The nested list starts at the first entry in entries (inclusive)
      # The nested list ends at the first entry in entries with depth min_h_num or greater (exclusive)
      def get_nest_entries(entries, min_h_num)
        entries.inject([]) do |nest_entries, entry|
          break nest_entries if entry[:h_num] == min_h_num

          nest_entries << entry
        end
      end

      def toc_headings
        @toc_levels.map { |level| "h#{level}" }.join(',')
      end

      def toc_headings_in_no_toc_section
        if @no_toc_section_class.is_a? Array
          @no_toc_section_class.map { |cls| toc_headings_within(cls) }.join(',')
        else
          toc_headings_within(@no_toc_section_class)
        end
      end

      def toc_headings_within(class_name)
        @toc_levels.map { |level| ".#{class_name} h#{level}" }.join(',')
      end

      def generate_option_hash(options)
        DEFAULT_CONFIG.merge(options)
      rescue TypeError
        DEFAULT_CONFIG
      end

      def lvl_opt_val(option, level=0, default=nil)
	# Enforce Level >= 0
	if !level.is_a?(Integer) or level < 0
          level = 0
        end
	# If the option is an array, we try to get the appropriate string by taking the level-th element
        if option.is_a?(Array)
          if option.length > level and option[level] != nil
	    return option[level]
	  elsif option.last != nil
            return option.last
	  else
	    return default
	  end
	# Is the option a hash, we look up level in the keys
	elsif option.is_a?(Hash)
	  opt_val = nil
	  option.each do |key, value|
            # If we got a string: Cast to int
            if key.is_a?(String)
              key = key.to_i
	    end
	    if key.is_a?(Integer) and key <= level
              opt_val = value
	    end
	  end
          return opt_val == nil ? default : opt_val
	else
	  return option == nil ? default : option
	end
      end
      def lvl_attr(name, option, level=0, default=nil)
        unless name.is_a?(String)
	  return ''
	end
        opt_val = lvl_opt_val(option, level, default)
	unless opt_val == nil or opt_val == ''
	  return "#{name}=\"#{opt_val}\" "
	else
          return ''
      end
    end
  end
end
