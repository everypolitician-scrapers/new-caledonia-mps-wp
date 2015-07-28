#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'wikidata/fetcher'

WikiData::Category.new('Catégorie:Membre du Congrès de la Nouvelle-Calédonie', 'fr').wikidata_ids.each do |id|
  data = WikiData::Fetcher.new(id: id).data or next
  puts data
  ScraperWiki.save_sqlite([:id], data)
end
