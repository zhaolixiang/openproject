#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2014 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

require 'spec_helper'
require_relative 'openid_connect_spec_helpers'

RSpec.configure do |c|
  c.include OpenIDConnectSpecHelpers
end

describe "OpenID Connect" do
  let(:provider) { OmniAuth::OpenIDConnect::Heroku.new }
  let(:user_info) do
    {
      :sub => "87117114115116",
      :name => "Hans Wurst",
      :email => "h.wurst@finn.de",
      :given_name => "Hans",
      :family_name => "Wurst"
    }
  end

  before do
    # The redirect will include an authorisation code.
    # Since we don't actually get a valid code in the test we will stub the resulting AccessToken.
    OpenIDConnect::Client.any_instance.stub(:access_token!) do
      OpenIDConnect::AccessToken.new :client => self, :access_token => "foo bar baz"
    end

    # Using the granted AccessToken the client then performs another request to the OpenID Connect
    # provider to retrieve user information such as name and email address.
    # Since the test is not supposed to make an actual call it is be stubbed too.
    OpenIDConnect::AccessToken.any_instance.stub(:userinfo!).and_return(
      OpenIDConnect::ResponseObject::UserInfo.new(user_info))

    # enable storing the access token in a cookie
    OpenProject::Configuration['omniauth_store_access_token_in_cookie'] = true
  end

  describe "sign-up and login" do
    before do
      Setting.stub(:plugin_openproject_openid_connect).and_return(
        {
          "providers" => {
            "heroku" => {
              "identifier" => "does not",
              "secret" => "matter"
            }
          }
        }
      )
    end

    after(:all) do
      User.delete_all
    end

    after do
      User.current = nil
    end

    it 'works' do
      ##
      # it should redirect to the provider's openid connect authentication endpoint
      click_on_signin

      expect(response.status).to be 302
      expect(response.location).to match /https:\/\/#{provider.host}.*$/

      params = Rack::Utils.parse_nested_query(response.location.gsub(/^.*\?/, ""))

      expect(params).to include "client_id"
      expect(params["redirect_uri"]).to match /^.*\/auth\/#{provider.class.provider_name}\/callback$/
      expect(params["scope"]).to include "openid"

      ##
      # it should redirect back from the provider to the login page
      redirect_from_provider

      expect(response.status).to be 302
      expect(response.location).to match /\/login$/

      ##
      # it should have created an account waiting to be activated
      expect(flash[:notice]).to match /account.*created/

      user = User.find_by_mail(user_info[:email])

      expect(user).not_to be nil
      expect(user.active?).to be false

      ##
      # it should redirect to the provider again upon clicking on sign-in when the user has been activated
      user = User.find_by_mail(user_info[:email])
      user.activate
      user.save!

      click_on_signin

      expect(response.status).to be 302
      expect(response.location).to match /https:\/\/#{provider.host}.*$/

      ##
      # it should then login the user upon the redirect back from the provider
      redirect_from_provider

      expect(response.status).to be 302
      expect(response.location).to match /my\/first_login$/

      # check that cookie is stored in the access token
      expect(response.cookies['_open_project_session_access_token']).to eq 'foo bar baz'
    end
  end

  context "provider configuration through the settings" do
    it "should make providers that are not configured unavailable" do
      get "/login"
      expect(response.body).not_to match /Google/i

      expect{click_on_signin("google")}.to raise_error(ActionController::RoutingError)
    end

    it "should make providers that have been configured through settings available without requiring a restart" do
      Setting.stub(:plugin_openproject_openid_connect).and_return(
        {
          "providers" => {
            "google" => {
              "identifier" => "does not",
              "secret" => "matter"
            }
          }
        }
      )

      get "/login"
      expect(response.body).to match /Google/i

      expect{click_on_signin("google")}.not_to raise_error
      expect(response.status).to be 302
    end
  end
end
