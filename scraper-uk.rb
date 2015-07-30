#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'pry'
require 'mediawiki_api'
require 'wikidata'
require 'colorize'
require 'diskcached'
require 'digest/sha1'
require 'set'

@cache = Diskcached.new(".cache", 60*60)
@unknown = Set.new

def category_to_wikibase(category, lang='en')
  client = MediawikiApi::Client.new "https://#{lang}.wikipedia.org/w/api.php"

  cat_args = { 
    cmtitle: category,
    token_type: false,
    list: 'categorymembers',
    cmlimit: '500'
  }
  response = @cache.cache("mems-#{category}") { client.action :query, cat_args }
  allids = response.data['categorymembers'].find_all { |m| m['ns'] == 0 }.map { |m| m['pageid'] }.sort
  while response['continue']
    cat_args[:cmcontinue] = response['continue']['cmcontinue']
    response = @cache.cache("mems-#{category}-#{cat_args[:cmcontinue]}") { client.action :query, cat_args }
    allids << response.data['categorymembers'].find_all { |m| m['ns'] == 0 }.map { |m| m['pageid'] }.sort
  end

  allids.flatten.each_slice(50).map { |ids|
    page_args = { 
      prop: 'pageprops',
      ppprop: 'wikibase_item',
      pageids: ids.join("|"),
      token_type: false,
    }
    response = @cache.cache("wbids-#{Digest::SHA1.hexdigest page_args[:pageids]}") { client.action :query, page_args }
    response.data['pages'].find_all { |p| p.last.key? 'pageprops' }.map { |p| p.last['pageprops']['wikibase_item'] }
  }.flatten
end

@skip = { 
  'P7' => 'Brother',
  'P9' => 'Sister',
  'P19' => 'Place of Birth',
  'P22' => 'Father',
  'P25' => 'Mother',
  'P26' => 'Spouse',
  'P27' => 'Country of Citizenship',
  'P31' => 'Instance of',
  'P39' => 'Position Held',
  'P69' => 'Educated at',
  'P91' => 'Sexual orientation',
  'P101' => 'Field of Work',
  'P103' => 'Native language',
  'P102' => 'Party',
  'P106' => 'Occupation', 
  'P108' => 'Employer', 
  'P140' => 'Religion',
  'P166' => 'Award received', 
  'P172' => 'Ethnic group',  # ?
  'P241' => 'Military branch', 
  'P361' => 'party of', 
  'P373' => 'Commons category', 
  'P410' => 'Military rank', 
  'P463' => 'Member of', 
  'P512' => 'Academic degree', 
  'P551' => 'Residence', 
  'P607' => 'Conflicts', 
  'P866' => 'Perlentaucher ID',
  'P900' => '<deleted>',
  'P910' => 'Main category',
  'P937' => 'Work location',
  'P990' => 'voice recording',
  'P1038' => 'Relative',
  'P1050' => 'Medical condition',
  'P1185' => 'Rodovid ID',
  'P1303' => 'instrument played',
  'P1343' => 'Described by source',
  'P1344' => 'Participant in',
  'P1412' => 'Languages',
  'P1447' => 'SportsReference ID',
  'P1819' => 'genealogics ID',
  'P1971' => 'Number of children',
}

@want = { 
  'P18' =>  [ 'image', 'url' ],
  'P21' =>  [ 'gender', 'title' ],
  'P213' => [ 'identifier__ISNI', 'value' ], 
  'P214' => [ 'identifier__VIAF', 'value' ], 
  'P227' => [ 'identifier__GND', 'value' ], 
  'P244' => [ 'identifier__LCAuth', 'value' ], 
  'P245' => [ 'identifier__ULAN', 'value' ], 
  'P268' => [ 'identifier__BNF', 'value' ], 
  'P269' => [ 'identifier__SUDOC', 'value' ], 
  'P345' => [ 'identifier__IMDB', 'value' ], 
  'P349' => [ 'identifier__NDL', 'value' ], 
  'P434' => [ 'identifier__MusicBrainz', 'value' ], 
  'P511' => [ 'honorific_prefix', 'title' ], 
  'P553' => [ 'website', 'title' ],
  'P569' => [ 'birth_date', 'date', 'to_date', 'to_s' ], 
  'P570' => [ 'death_date', 'date', 'to_date', 'to_s' ], 
  'P646' => [ 'identifier__freebase', 'value' ],
  'P734' => [ 'family_name', 'title' ],
  'P735' => [ 'given_name', 'title' ],
  'P856' => [ 'website', 'value' ],
  'P968' => [ 'email', 'value' ],
  'P1006' => [ 'identifier__NTA', 'value' ], 
  'P1035' => [ 'honorific_suffix', 'title' ], 
  'P1045' => [ 'identifier__sycomore', 'value' ],
  'P1186' => [ 'identifier__EuroparlMEP', 'value' ], 
  'P1263' => [ 'identifier__NNDB', 'value' ], 
  'P1273' => [ 'identifier__CANTIC', 'value' ], 
  'P1284' => [ 'identifier__Muzinger', 'value' ], 
  'P1430' => [ 'identifier__OpenPlaques', 'value' ], 
  'P1477' => [ 'birth_name', 'value' ], 
  'P1714' => [ 'identifier__journalisted', 'value' ], 
  'P1808' => [ 'identifier__senatDOTfr', 'value' ], 
  'P1816' => [ 'identifier__NPG', 'value' ], 
  'P1996' => [ 'identifier__parliamentDOTuk', 'value' ], 
  'P1953' => [ 'identifier__discogs', 'value' ], 
}

def wikidata(qcode, lang)
  return if qcode.to_s.empty?

  wd = @cache.cache("wikidata-#{qcode}") { Wikidata::Item.find qcode }
  return unless wd && wd.hash.key?('claims')

  claims = (wd.hash['claims'] || {}).keys.sort_by { |p| p[1..-1].to_i }

  #TODO: other languages
  data = {
    id: wd.id,
    name: wd.labels[lang].value,
  }

  claims.find_all { |c| !@skip[c] && !@want[c] &&!@unknown.include?(c) }.each do |c|
    puts "Unknown claim: https://www.wikidata.org/wiki/Property:#{c}".red
    @unknown << c
  end

  claims.find_all { |c| @want.key? c }.each do |c|
    att, meth, *more = @want[c]
    att = att.to_sym
    begin
      data[att] = wd.property(c).send(meth) 
      data[att] = more.inject(data[att]) { |acc, n| acc.send(n) }
    rescue => e
      warn "#{e} with #{meth} on #{c}".red
      # binding.pry unless c == 'P1477'
    end
  end
  data
end


@CAT = 'Category:UK MPs 2015–20'
@LANG = 'en'

ids = category_to_wikibase(@CAT, @LANG)
ids.each do |id|
  next unless data = wikidata(id, @LANG) 
  puts data
  ScraperWiki.save_sqlite([:id], data)
end
