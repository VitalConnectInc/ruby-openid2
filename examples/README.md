This directory contains several examples that demonstrate use of the
OpenID library.  Make sure you have properly installed the library
before running the examples.  These examples are a great place to
start in integrating OpenID into your application.

## Rails example

The `rails_openid` directory contains a fully functional OpenID server and relying
party, and acts as a starting point for implementing your own
production rails server.  You'll need the latest version of Ruby on
Rails installed, and then:

```shell
cd rails_openid
./script/server
```

Open a web browser to http://localhost:3000/ and follow the instructions.

The relevant code to work from when writing your Rails OpenID Relying
Party is:

  rails_openid/app/controllers/consumer_controller.rb

If you are working on an OpenID provider, check out

  rails_openid/app/controllers/server_controller.rb

Since the library and examples are Apache-licensed, don't be shy about
copy-and-paste.

## Rails ActiveRecord OpenIDStore plugin

For various reasons you may want or need to deploy your ruby openid
consumer/server using an SQL based store.  The `active_record_openid_store`
is a plugin that makes using an SQL based store simple.  Follow the
README inside the plugin's dir for usage.
