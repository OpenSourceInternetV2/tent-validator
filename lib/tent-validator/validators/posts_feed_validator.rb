module TentValidator
  class PostsFeedValidator < TentValidator::Spec

    require 'tent-validator/validators/support/post_generators'
    include Support::PostGenerators

    require 'tent-validator/validators/support/app_post_generators'
    include Support::AppPostGenerators

    require 'tent-validator/validators/support/oauth'
    include Support::OAuth

    def create_post(client, attrs)
      res = client.post.create(attrs)
      raise SetupFailure.new("Failed to create post!", res) unless res.success?
      res.body['post']
    end

    def create_posts
      client = clients(:app_auth)

      posts = []

      timestamp = TentD::Utils.timestamp
      posts << create_post(client, generate_status_post.merge(:published_at => timestamp, :content => {:text => "first or second post A"}))
      posts << create_post(client, generate_fictitious_post.merge(:published_at => timestamp, :content => {:text => "first or second post B"}))
      posts << create_post(client, generate_status_reply_post.merge(:published_at => TentD::Utils.timestamp, :content => {:text => "third post"}))
      posts << create_post(client, generate_status_post.merge(:published_at => TentD::Utils.timestamp, :content => {:text => "fourth post"}))
      timestamp = TentD::Utils.timestamp
      posts << create_post(client, generate_status_post.merge(:published_at => timestamp, :content => {:text => "fifth or sixth post A"}))
      posts << create_post(client, generate_fictitious_post.merge(:published_at => timestamp, :content => {:text => "fifth or sixth post B"}))

      set(:posts, posts)

      types = posts.map { |post| post['type'] }.reverse
      set(:types, types)
    end

    def create_posts_with_mentions
      client = clients(:app_auth)
      posts = []

      _create_post = proc do |attrs|
        post = create_post(client, attrs)
        posts << post
        post
      end

      _ref = _create_post.call(generate_status_post)
      _create_post.call(generate_status_reply_post.merge(:mentions => [{ :entity => _ref['entity'], :post => _ref['id']}]))

      _ref = _create_post.call(generate_status_post)
      _create_post.call(generate_status_reply_post.merge(:mentions => [{ :entity => _ref['entity'], :post => _ref['id']}]))

      set(:mentions_posts, posts)
    end

    def create_private_posts
      client = clients(:app_auth)
      posts = []

      posts << create_post(client, generate_status_post(is_public=false))
      posts << create_post(client, generate_status_reply_post(is_public=false))
      posts << create_post(client, generate_status_post(is_public=false))

      set(:private_posts, posts)
    end

    describe "GET posts_feed", :before => :create_posts do
      context "without params" do
        expect_response(:status => 200, :schema => :data) do
          expect_properties(:posts => get(:types).map { |type| { :type => type } })

          clients(:app_auth).post.list
        end

        expect_response(:status => 200) do
          expect_headers('Count' => /\A\d+\Z/)

          clients(:app_auth).post.head.list
        end
      end

      context "with type param" do
        expect_response(:status => 200, :schema => :data) do
          types = get(:types)
          types = [types.first, types.last]

          expect_properties(:posts => types.map { |type| { :type => type } })

          clients(:app_auth).post.list(:types => types.join(","))
        end

        expect_response(:status => 200) do
          expect_headers('Count' => /\A\d+\Z/)

          types = get(:types)
          types = [types.first, types.last]

          clients(:app_auth).post.head.list(:types => types.join(","))
        end

        context "when using fragment wildcard" do
          expect_response(:status => 200, :schema => :data) do
            type = TentClient::TentType.new('https://tent.io/types/status/v0')
            expected_types = get(:types).select { |t|
              TentClient::TentType.new(t).base == type.base
            }.map { |t| { :type => t } }

            expect_properties(:posts => expected_types)

            clients(:app_auth).post.list(:types => type.to_s(:fragment => false))
          end

          expect_response(:status => 200) do
            expect_headers('Count' => /\A\d+\Z/)

            type = TentClient::TentType.new('https://tent.io/types/status/v0')

            clients(:app_auth).post.head.list(:types => type.to_s(:fragment => false))
          end
        end
      end

      context "with entities param" do
        context "when no matching entities" do
          expect_response(:status => 200, :schema => :data) do
            expect_properties(:posts => [])

            clients(:app_auth).post.list(:entities => "https://fictitious.entity.example.org")
          end

          expect_response(:status => 200) do
            expect_headers('Count' => '0')

            clients(:app_auth).post.head.list(:entities => "https://fictitious.entity.example.org")
          end
        end

        context "when matching entities" do
          expect_response(:status => 200, :schema => :data) do
            entities = get(:posts).map { |p| p['entity'] }
            expect_properties(:posts => entities.map { |e| { :entity => e } })

            clients(:app_auth).post.list(:entities => entities.uniq.join(','))
          end

          expect_response(:status => 200) do
            expect_headers('Count' => /\A\d+\Z/)

            entities = get(:posts).map { |p| p['entity'] }

            clients(:app_auth).post.head.list(:entities => entities.uniq.join(','))
          end
        end

        # TODO: validate feed with entities param (with proxy)
      end

      context "when using default sort order" do
        expect_response(:status => 200, :schema => :data) do
          posts = get(:posts).sort_by { |post| post['received_at'].to_i * -1 }
          expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'received_at') })

          clients(:app_auth).post.list(:sort_by => 'received_at')
        end

        expect_response(:status => 200) do
          expect_headers('Count' => /\A\d+\Z/)

          clients(:app_auth).post.head.list(:sort_by => 'received_at')
        end
      end

      context "with sort_by param" do
        context "when received_at" do
          expect_response(:status => 200, :schema => :data) do
            posts = get(:posts).sort_by { |post| post['received_at'].to_i * -1 }
            expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'received_at') })

            clients(:app_auth).post.list(:sort_by => 'received_at')
          end

          expect_response(:status => 200) do
            expect_headers('Count' => /\A\d+\Z/)

            clients(:app_auth).post.head.list(:sort_by => 'received_at')
          end
        end

        context "when published_at" do
          expect_response(:status => 200, :schema => :data) do
            posts = get(:posts).sort_by { |post| post['published_at'].to_i * -1 }
            expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })

            clients(:app_auth).post.list(:sort_by => 'published_at')
          end

          expect_response(:status => 200) do
            expect_headers('Count' => /\A\d+\Z/)

            clients(:app_auth).post.head.list(:sort_by => 'published_at')
          end
        end

        context "when version.received_at" do
          expect_response(:status => 200, :schema => :data) do
            posts = get(:posts).sort_by { |post| post['version']['received_at'].to_i * -1 }
            expect_properties(:posts => posts.map { |post| { :version => TentD::Utils::Hash.slice(post['version'], 'received_at') } })

            clients(:app_auth).post.list(:sort_by => 'version.received_at')
          end

          expect_response(:status => 200) do
            expect_headers('Count' => /\A\d+\Z/)

            clients(:app_auth).post.head.list(:sort_by => 'version.received_at')
          end
        end

        context "when version.published_at" do
          expect_response(:status => 200, :schema => :data) do
            posts = get(:posts).sort_by { |post| post['version']['published_at'].to_i * -1 }
            expect_properties(:posts => posts.map { |post| { :version => TentD::Utils::Hash.slice(post['version'], 'published_at') } })

            clients(:app_auth).post.list(:sort_by => 'version.published_at')
          end

          expect_response(:status => 200) do
            expect_headers('Count' => /\A\d+\Z/)

            clients(:app_auth).post.head.list(:sort_by => 'version.published_at')
          end
        end
      end

      context "pagination" do
        set :sorted_posts do
          get(:posts).sort do |a,b|
            i = a['published_at'] <=> b['published_at']
            i == 0 ? a['version']['id'] <=> b['version']['id'] : i
          end
        end

        context "with since param" do
          context "using timestamp" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              since_post = posts.shift
              since = since_post['published_at']

              limit = 2
              posts = posts.slice(1, limit).reverse # second post has the same timestamp as the first

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'id', 'published_at') })

              clients(:app_auth).post.list(:since => since, :sort_by => :published_at, :limit => limit)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts)

              since_post = posts.shift
              since = since_post['published_at']

              limit = 2

              clients(:app_auth).post.head.list(:since => since, :sort_by => :published_at, :limit => limit)
            end
          end

          context "using timestamp + version" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              since_post = posts.shift
              since = "#{since_post['published_at']} #{since_post['version']['id']}"

              limit = 2
              posts = posts.slice(0, limit).reverse

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'id', 'published_at') })

              clients(:app_auth).post.list(:since => since, :sort_by => :published_at, :limit => limit)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts)

              since_post = posts.shift
              since = "#{since_post['published_at']} #{since_post['version']['id']}"

              limit = 2

              clients(:app_auth).post.head.list(:since => since, :sort_by => :published_at, :limit => limit)
            end
          end
        end

        context "with until param" do
          context "using timestamp" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              until_post = posts.shift
              posts.shift # has the same published_at
              until_param = until_post['published_at']

              posts = posts.reverse

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:until => until_param, :sort_by => :published_at)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts)

              until_post = posts.shift
              posts.shift # has the same published_at
              until_param = until_post['published_at']

              posts = posts.reverse

              expect_headers('Count' => posts.size.to_s)

              clients(:app_auth).post.head.list(:until => until_param, :sort_by => :published_at)
            end
          end

          context "using timestamp + version" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              until_post = posts.shift
              until_param = [until_post['published_at'], until_post['version']['id']].join(' ')

              posts = posts.reverse

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'id', 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:until => until_param, :sort_by => :published_at)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts)

              until_post = posts.shift
              until_param = [until_post['published_at'], until_post['version']['id']].join(' ')

              posts = posts.reverse

              expect_headers('Count' => posts.size.to_s)

              clients(:app_auth).post.head.list(:until => until_param, :sort_by => :published_at)
            end
          end
        end

        context "with before param" do
          context "using timestamp" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # has the same timestamp, don't expect it
              before = before_post['published_at']

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :sort_by => :published_at, :limit => posts.size)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # has the same timestamp, don't expect it
              before = before_post['published_at']

              clients(:app_auth).post.head.list(:before => before, :sort_by => :published_at, :limit => posts.size)
            end
          end

          context "using timestamp + version" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :sort_by => :published_at, :limit => posts.size)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              clients(:app_auth).post.head.list(:before => before, :sort_by => :published_at, :limit => posts.size)
            end
          end
        end

        context "with before and since params" do
          context "using timestamp" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # same timestamp
              before = before_post['published_at']

              since_post = posts.pop
              posts.pop # same timestamp
              since = since_post['published_at']

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :since => since, :sort_by => :published_at)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # same timestamp
              before = before_post['published_at']

              since_post = posts.pop
              posts.pop # same timestamp
              since = since_post['published_at']

              expect_headers('Count' => posts.size.to_s)

              clients(:app_auth).post.head.list(:before => before, :since => since, :sort_by => :published_at)
            end

            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              before_post = posts.pop
              posts.pop # same timestamp
              before = before_post['published_at']

              since_post = posts.shift
              posts.shift # same timestamp
              since = since_post['published_at']

              limit = 1
              posts = posts.slice(0, limit).reverse # third post

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :since => since, :sort_by => :published_at, :limit => limit)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts)

              before_post = posts.pop
              posts.pop # same timestamp
              before = before_post['published_at']

              since_post = posts.shift
              posts.shift # same timestamp
              since = since_post['published_at']

              limit = 1

              clients(:app_auth).post.head.list(:before => before, :since => since, :sort_by => :published_at, :limit => limit)
            end
          end

          context "using timestamp + version" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              since_post = posts.pop
              since = [since_post['published_at'], since_post['version']['id']].join(' ')

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :since => since, :sort_by => :published_at)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              since_post = posts.pop
              since = [since_post['published_at'], since_post['version']['id']].join(' ')

              expect_headers('Count' => posts.size.to_s)

              clients(:app_auth).post.head.list(:before => before, :since => since, :sort_by => :published_at)
            end

            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              before_post = posts.pop
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              since_post = posts.shift
              since = [since_post['published_at'], since_post['version']['id']].join(' ')

              limit = 2
              posts = posts.slice(0, limit).reverse # second post, thrid post

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :since => since, :sort_by => :published_at, :limit => limit)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts)

              before_post = posts.pop
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              since_post = posts.shift
              since = [since_post['published_at'], since_post['version']['id']].join(' ')

              limit = 2

              clients(:app_auth).post.head.list(:before => before, :since => since, :sort_by => :published_at, :limit => limit)
            end
          end
        end

        context "with before and until params" do
          context "using timestamp" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # same timestamp
              before = before_post['published_at']

              until_post = posts.pop
              posts.pop # same timestamp
              until_param = until_post['published_at']

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :until => until_param, :sort_by => :published_at)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # same timestamp
              before = before_post['published_at']

              until_post = posts.pop
              posts.pop # same timestamp
              until_param = until_post['published_at']

              expect_headers('Count' => posts.size.to_s)

              clients(:app_auth).post.head.list(:before => before, :until => until_param, :sort_by => :published_at)
            end

            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # same timestamp
              before = before_post['published_at']

              until_post = posts.pop
              posts.pop # same timestamp
              until_param = until_post['published_at']

              limit = 1
              posts = posts.slice(0, limit)

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :until => until_param, :sort_by => :published_at, :limit => limit)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              posts.shift # same timestamp
              before = before_post['published_at']

              until_post = posts.pop
              posts.pop # same timestamp
              until_param = until_post['published_at']

              limit = 1
              posts = posts.slice(0, limit)

              expect_headers('Count' => /\A\d+\Z/)

              clients(:app_auth).post.head.list(:before => before, :until => until_param, :sort_by => :published_at, :limit => limit)
            end
          end

          context "using timestamp + version" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              until_post = posts.pop
              until_param = [until_post['published_at'], until_post['version']['id']].join(' ')

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :until => until_param, :sort_by => :published_at)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              until_post = posts.pop
              until_param = [until_post['published_at'], until_post['version']['id']].join(' ')

              expect_headers('Count' => posts.size.to_s)

              clients(:app_auth).post.head.list(:before => before, :until => until_param, :sort_by => :published_at)
            end

            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              until_post = posts.pop
              until_param = [until_post['published_at'], until_post['version']['id']].join(' ')

              limit = 2
              posts = posts.slice(0, limit)

              expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
              expect_property_length('/posts', posts.size)

              clients(:app_auth).post.list(:before => before, :until => until_param, :sort_by => :published_at, :limit => limit)
            end

            expect_response(:status => 200) do
              posts = get(:sorted_posts).reverse

              before_post = posts.shift
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              until_post = posts.pop
              until_param = [until_post['published_at'], until_post['version']['id']].join(' ')

              limit = 2

              expect_headers('Count' => /\A\d+\Z/)

              clients(:app_auth).post.head.list(:before => before, :until => until_param, :sort_by => :published_at, :limit => limit)
            end
          end
        end

        describe "pages links" do
          context "when middle page" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              # posts
              # | newest |
              # - 6
              # - 5
              # - 4 < before post
              # - 3 <
              # - 2 <
              # - 1
              # | oldest |

              # prev page
              # | newest |
              # - 6 <
              # - 5 <
              # - 4
              # - 3
              # - 2
              # - 1
              # | oldest |

              # next page
              # | newest |
              # - 6
              # - 5
              # - 4
              # - 3
              # - 2
              # - 1 <
              # | oldest |

              i = 3 # fourth post
              set(:before_post_index, i)
              before_post = posts[i]
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              limit = 2
              set(:limit, limit)

              res = clients(:app_auth).post.list(:limit => limit, :before => before, :sort_by => :published_at)

              set(:pages, res.body['pages']) if res.success?

              res
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts)

              i = 3 # fourth post
              before_post = posts[i]
              before = [before_post['published_at'], before_post['version']['id']].join(' ')

              limit = 2

              clients(:app_auth).post.head.list(:limit => limit, :before => before, :sort_by => :published_at)
            end

            describe "`pages.next`" do
              expect_response(:status => 200, :schema => :data) do
                pages = get(:pages) || {}
                next_params = parse_params(pages['next'].to_s)

                posts = get(:sorted_posts).reverse.slice(get(:before_post_index) + get(:limit), get(:limit)) # first post

                expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
                expect_property_length('/posts', 2) # first post + some other post (at least the meta post will be there)

                clients(:app_auth).post.list(next_params)
              end

              expect_response(:status => 200) do
                expect_headers('Count' => /\A\d+\Z/)

                pages = get(:pages) || {}
                next_params = parse_params(pages['next'].to_s)

                clients(:app_auth).post.head.list(next_params)
              end
            end

            describe "`pages.prev`" do
              expect_response(:status => 200, :schema => :data) do
                pages = get(:pages) || {}
                prev_params = parse_params(pages['prev'].to_s)

                posts = get(:sorted_posts).reverse.slice(0, get(:before_post_index)).reverse.slice(0, get(:limit)).reverse

                expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
                expect_property_length('/posts', posts.size)

                clients(:app_auth).post.list(prev_params)
              end

              expect_response(:status => 200) do
                expect_headers('Count' => /\A\d+\Z/)

                pages = get(:pages) || {}
                prev_params = parse_params(pages['prev'].to_s)

                clients(:app_auth).post.head.list(prev_params)
              end
            end

            describe "`pages.first`" do
              expect_response(:status => 200, :schema => :data) do
                pages = get(:pages) || {}
                first_params = parse_params(pages['first'].to_s)

                posts = get(:sorted_posts).reverse.slice(0, get(:limit))

                expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
                expect_property_length('/posts', posts.size)

                clients(:app_auth).post.list(first_params)
              end

              expect_response(:status => 200) do
                expect_headers('Count' => /\A\d+\Z/)

                pages = get(:pages) || {}
                first_params = parse_params(pages['first'].to_s)

                clients(:app_auth).post.head.list(first_params)
              end
            end

            describe "`pages.last`" do
              expect_response(:status => 200, :schema => :data) do
                res = clients(:app_auth).post.list(:sort_by => :published_at, :limit => 2, :since => 0)
                set(:last_posts, res.body['posts']) if res.success?
                res
              end

              expect_response(:status => 200) do
                expect_headers('Count' => /\A\d+\Z/)

                clients(:app_auth).post.head.list(:sort_by => :published_at, :limit => 2, :since => 0)
              end

              expect_response(:status => 200, :schema => :data) do
                pages = get(:pages) || {}
                last_params = parse_params(pages['last'].to_s)

                posts = get(:last_posts).to_a

                expect_properties(:posts => posts.map { |post| TentD::Utils::Hash.slice(post, 'published_at') })
                expect_property_length('/posts', posts.size)

                clients(:app_auth).post.list(last_params)
              end

              expect_response(:status => 200) do
                expect_headers('Count' => /\A\d+\Z/)

                pages = get(:pages) || {}
                last_params = parse_params(pages['last'].to_s)

                clients(:app_auth).post.head.list(last_params)
              end
            end
          end

          context "when first page" do
            expect_response(:status => 200, :schema => :data) do
              posts = get(:sorted_posts)

              expect_properties_absent('/pages/first', '/pages/prev')
              expect_properties_present('/pages/last', '/pages/next')

              limit = 2
              set(:limit, limit)

              clients(:app_auth).post.list(:limit => limit, :sort_by => :published_at)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              posts = get(:sorted_posts)

              limit = get(:limit)
              clients(:app_auth).post.head.list(:limit => limit, :sort_by => :published_at)
            end
          end

          context "when last page" do
            expect_response(:status => 200, :schema => :data) do
              expect_properties_absent('/pages/last', '/pages/next')
              expect_properties_present('/pages/first', '/pages/prev')

              limit = 2
              set(:limit, limit)

              clients(:app_auth).post.list(:limit => limit, :sort_by => :published_at, :since => 0)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              limit = get(:limit)
              clients(:app_auth).post.head.list(:limit => limit, :sort_by => :published_at, :since => 0)
            end
          end
        end
      end

      context "with limit param" do
        expect_response(:status => 200, :schema => :data) do
          expect_property_length("/posts", 2)

          clients(:app_auth).post.list(:limit => 2)
        end

        expect_response(:status => 200, :schema => :data) do
          expect_headers('Count' => /\A\d+\Z/)

          clients(:app_auth).post.head.list(:limit => 2)
        end
      end

      # default limit is 25, make sure there are more than 25 posts (create_posts already called once and it creates 4 posts)
      context "when using default limit", :before => 6.times.map { :create_posts } do
        expect_response(:status => 200, :schema => :data) do
          expect_property_length("/posts", 25)

          clients(:app_auth).post.list
        end

        expect_response(:status => 200) do
          expect_headers('Count' => /\A\d+\Z/)

          clients(:app_auth).post.head.list
        end
      end

      context "with mentions param", :before => :create_posts_with_mentions do
        context "when single param" do
          context "entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              posts = get(:mentions_posts).select { |post|
                post['mentions'] && post['mentions'].any? { |m| m['entity'] == entity || m['entity'].nil? }
              }.reverse

              expect_properties(:posts => posts.map { |post| {:published_at => post['published_at']} })
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:post=>m['post']} } } })

              clients(:app_auth).post.list(:mentions => entity)
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity

              expect_headers('Count' => /\A\d+\Z/)

              clients(:app_auth).post.head.list(:mentions => entity)
            end
          end

          context "entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              post = get(:mentions_posts).first['id'] # first status post
              posts = [get(:mentions_posts)[1]] # first status post reply

              expect_properties(:posts => posts.map { |post| {:id => post['id']} })
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:entity => property_absent, :post=>m['post']} } } })

              clients(:app_auth).post.list(:mentions => [entity, post].join(' '))
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              entity = get(:mentions_posts).first['entity'] # remote entity
              post = get(:mentions_posts).first['id'] # first status post

              clients(:app_auth).post.head.list(:mentions => [entity, post].join(' '))
            end
          end

          context "entity OR entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              posts = get(:mentions_posts).select { |post|
                post['mentions'] && post['mentions'].any? { |m| m['entity'] == entity || m['entity'].nil? }
              }.reverse

              expect_properties(:posts => posts.map { |post| {:published_at => post['published_at']} })
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:post=>m['post']} } } })

              clients(:app_auth).post.list(:mentions => [entity, fictitious_entity].join(','))
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server

              clients(:app_auth).post.head.list(:mentions => [entity, fictitious_entity].join(','))
            end
          end

          context "entity OR entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              post = get(:mentions_posts).first['id'] # first status post
              posts = [get(:mentions_posts)[1]] # first status post reply

              expect_properties(:posts => posts.map { |post| {:id => post['id']} })
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:entity=>property_absent,:post=>m['post']} } } })

              clients(:app_auth).post.list(:mentions => [fictitious_entity, [entity, post].join(' ')].join(','))
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              post = get(:mentions_posts).first['id'] # first status post

              clients(:app_auth).post.head.list(:mentions => [fictitious_entity, [entity, post].join(' ')].join(','))
            end
          end
        end

        context "when multiple params" do
          context "entity AND entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server

              expect_properties(:posts => [])

              clients(:app_auth).post.list(:mentions => [fictitious_entity, entity])
            end

            expect_response(:status => 200) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server

              expect_headers('Count' => '0')

              clients(:app_auth).post.head.list(:mentions => [fictitious_entity, entity])
            end
          end

          context "entity AND entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              post = get(:mentions_posts).first['id'] # first status post
              posts = [get(:mentions_posts)[1]] # first status post reply

              expect_properties(:posts => posts.map { |post| {:id => post['id']} })

              clients(:app_auth).post.list(:mentions => [entity, [entity, post].join(' ')])
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              entity = get(:mentions_posts).first['entity'] # remote entity
              post = get(:mentions_posts).first['id'] # first status post

              clients(:app_auth).post.head.list(:mentions => [entity, [entity, post].join(' ')])
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              post = get(:mentions_posts).first['id'] # first status post

              expect_properties(:posts => [])

              clients(:app_auth).post.list(:mentions => [fictitious_entity, [entity, post].join(' ')])
            end

            expect_response(:status => 200) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              post = get(:mentions_posts).first['id'] # first status post

              expect_headers('Count' => '0')

              clients(:app_auth).post.head.list(:mentions => [fictitious_entity, [entity, post].join(' ')])
            end
          end

          context "(entity OR entity) AND entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              posts = [get(:mentions_posts).last] # first status post reply

              expect_properties(:posts => posts.map { |post| {:id => post['id']} })

              clients(:app_auth).post.list(:mentions => [[fictitious_entity, entity].join(','), entity])
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server

              clients(:app_auth).post.head.list(:mentions => [[fictitious_entity, entity].join(','), entity])
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"

              expect_properties(:posts => [])

              clients(:app_auth).post.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), entity])
            end

            expect_response(:status => 200) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"

              expect_headers('Count' => '0')

              clients(:app_auth).post.head.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), entity])
            end
          end

          context "(entity OR entity) AND (entity OR entity)" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              posts = [get(:mentions_posts).last] # first status post reply

              expect_properties(:posts => posts.map { |post| {:id => post['id']} })

              clients(:app_auth).post.list(:mentions => 2.times.map { [fictitious_entity, entity].join(',') })
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server

              clients(:app_auth).post.head.list(:mentions => 2.times.map { [fictitious_entity, entity].join(',') })
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"

              expect_properties(:posts => [])

              clients(:app_auth).post.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), [fictitious_entity, entity].join(',')])
            end

            expect_response(:status => 200) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"

              expect_headers('Count' => '0')

              clients(:app_auth).post.head.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), [fictitious_entity, entity].join(',')])
            end
          end

          context "(entity OR entity) AND entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              post = get(:mentions_posts).first['id'] # first status post

              expect_properties(:posts => [])

              clients(:app_auth).post.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), [entity, post].join(' ')])
            end

            expect_response(:status => 200) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              post = get(:mentions_posts).first['id'] # first status post

              expect_headers('Count' => '0')

              clients(:app_auth).post.head.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), [entity, post].join(' ')])
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              post = get(:mentions_posts).first['id'] # first status post
              posts = [get(:mentions_posts)[1]] # first status post reply

              expect_properties(:posts => posts.map { |post| {:id => post['id']} })

              clients(:app_auth).post.list(:mentions => [[fictitious_entity, entity].join(','), [entity, post].join(' ')])
            end

            expect_response(:status => 200, :schema => :data) do
              expect_headers('Count' => /\A\d+\Z/)

              entity = get(:mentions_posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              post = get(:mentions_posts).first['id'] # first status post

              clients(:app_auth).post.head.list(:mentions => [[fictitious_entity, entity].join(','), [entity, post].join(' ')])
            end
          end
        end
      end

      context "without authentication", :before => :create_private_posts do
        expect_response(:status => 200, :schema => :data) do
          expect_properties(:posts => 2.times.map { {:permissions => property_absent} })
          expect_property_length('/posts', 2)

          clients(:no_auth).post.list(:limit => 2)
        end

        expect_response(:status => 200) do
          expect_headers('Count' => /\A\d+\Z/)

          clients(:no_auth).post.head.list(:limit => 2)
        end
      end

      context "with authentication", :before => :create_private_posts do
        context "with full authorization" do
          expect_response(:status => 200, :schema => :data) do
            posts = get(:private_posts)
            expect_properties(:posts => posts.reverse.slice(0, 2).map { |post| TentD::Utils::Hash.slice(post, 'id', 'permissions') })
            expect_property_length('/posts', 2)

            clients(:app_auth).post.list(:limit => 2)
          end

          expect_response(:status => 200) do
            expect_headers('Count' => /\A\d+\Z/)

            clients(:app_auth).post.head.list(:limit => 2)
          end
        end

        context "with limited authorization" do
          context "when limited fragment" do
            authenticate_with_permissions(:read_types => %w(https://tent.io/types/status/v0#))

            expect_response(:status => 200, :schema => :data) do
              expect_properties(:posts => 2.times.map { {:type => "https://tent.io/types/status/v0#"} })
              expect_property_length('/posts', 2)

              get(:client).post.list(:limit => 2)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              get(:client).post.head.list(:limit => 2)
            end
          end

          context "when limited base" do
            authenticate_with_permissions(:read_types => %w(https://tent.io/types/status/v0))

            expect_response(:status => 200, :schema => :data) do
              expect_properties(:posts => 2.times.map {
                { :type => %r{\Ahttps://tent\.io/types/status/v0#} }
              })
              expect_property_length('/posts', 2)

              get(:client).post.list(:limit => 2)
            end

            expect_response(:status => 200) do
              expect_headers('Count' => /\A\d+\Z/)

              get(:client).post.head.list(:limit => 2)
            end
          end
        end
      end
    end
  end

  TentValidator.validators << PostsFeedValidator
end
