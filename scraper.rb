#!/bin/env ruby
# encoding: utf-8

require 'wikidata/fetcher'

names = WikiData::Category.new('Catégorie:Membre du Congrès de la Nouvelle-Calédonie', 'fr').member_titles
EveryPolitician::Wikidata.scrape_wikidata(names: { fr: names })
