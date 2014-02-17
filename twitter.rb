# encoding: utf-8

require 'net/http'
require 'uri'
require 'base64'
require 'cgi'
require 'json'
require 'open-uri'

class AppOnlyAuth
	def set_url(url)
		@url = url
	end

	def set_key(key)
		@key = key
	end

	def set_secret(secret)
		@secret = secret
	end

	def get_token()
		create_credential
		send
		return @token
	end

	private
	def create_credential()
		token_credential = CGI.escape(@key) +':'+ CGI.escape(@secret)
		@credential = Base64.strict_encode64(token_credential)
	end

	def send()
		uri = URI.parse(@url)
		request = Net::HTTP::Post.new(uri.path)
		request['Content-Type'] = 'application/x-www-form-urlencoded'
		request['Authorization'] = 'Basic ' + @credential
		request.set_form_data({'grant_type'=>'client_credentials'})

		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = true
		response = http.request(request)

		parsed = JSON.parse(response.body) 
		@token = parsed['access_token']
	end
end

class TwitSearch
	attr_reader :query
	def set_url(url)
		@url = url
	end	

	def set_token(token)
		@token = token
	end

	def set_query(query)
		#ハッシュの場合はencode_www_formにてエンコードを行う
		if query.instance_of?(Hash) then
			@query = URI.encode_www_form(query)
		elsif query.instance_of?(String) then
			@query = query.delete('?')
		end
	end

	def fetch()
		uri = URI.parse(@url)
		uri.query = @query
		request = Net::HTTP::Get.new(uri.request_uri)
		request['Content-Type'] = 'application/x-www-form-urlencoded'
		request['Authorization'] = 'Bearer ' + @token

		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = true
		#HTTPデバッグ
		#http.set_debug_output $stderr
		response = http.request(request)

		parsed = JSON.parse(response.body)

		return parsed
	end

	def iterator
		TwitIterator.new(self)
	end
end

class TwitIterator
	def initialize(twit_search)
		@twit_search = twit_search
		#次の検索結果が存在するか
		@has_next = true
	end

	def has_next?
		@has_next
	end

	def next
		parsed = @twit_search.fetch()

		if parsed['search_metadata'].key?('next_results') then
			@has_next = true
			query = parsed['search_metadata']['next_results']
			@twit_search.set_query(query)
		else
			@has_next = false
		end

		return parsed
	end
end

class ImageDownloader
	
end


AUTH_API_URL = 'https://api.twitter.com/oauth2/token'
CONSUMER_KEY = ''
CONSUMER_SECRET = ''
SEARCH_API_URL = 'https://api.twitter.com/1.1/search/tweets.json'


app_only_auth = AppOnlyAuth.new
app_only_auth.set_url(AUTH_API_URL)
app_only_auth.set_key(CONSUMER_KEY)
app_only_auth.set_secret(CONSUMER_SECRET)
access_token = app_only_auth.get_token()

ts = TwitSearch.new
ts.set_url(SEARCH_API_URL)
ts.set_token(access_token)
param = {
	'q' => ARGV[0],
	'count' => 100,
	'include_entities' => true
}
puts param
ts.set_query(param)
ti = ts.iterator()

c = 0
while ti.has_next? do
	parsed = ti.next()
	puts '取得ツイート数: ' + parsed['statuses'].length.to_s
	c += parsed['statuses'].length
	parsed['statuses'].each do |tweet|
		if tweet['entities'].key?('media') then
			tweet['entities']['media'].each do |media|
				file_name = File.basename(media['media_url'])
				dir_name = './image/'
				file_path = dir_name + file_name

				open(file_path, 'wb') do |file|
					open(media['media_url']) do |data|
						file.write(data.read)
					end
				end
			end
		end
	end
end
puts '合計ツイート数: ' + c.to_s
