# frozen_string_literal: true

require "abstract_unit"

class URITest < ActiveSupport::TestCase
  def setup
  end

  test "build_from_string" do
    uri = ActionDispatch::Http::URI.build_from_string("http://myapp.test/page?id#me")
    assert_equal uri.to_s, "http://myapp.test/page?id#me"
    assert_equal uri.scheme, "http"
    assert_equal uri.protocol, "http://"
    assert_equal uri.host, "myapp.test"
    assert_equal uri.path, "/page"
    assert_equal uri.fragment, "me"
  end

  test "build/change uri after creation" do
    uri = ActionDispatch::Http::URI.build_from_string("http://myapp.test/page?id#me")
    uri.port = 444

    assert_equal false, uri.standard_port?
    assert_equal 80, uri.standard_port
    assert_equal ":444", uri.port_string
    uri.host = "we.are"
    assert_equal "we.are:444", uri.host_with_port
  end

  test "build_from_faulty_string" do
    uri = ActionDispatch::Http::URI.build_from_faulty_string("http://2001:0db8:85a3:0000:0000:8a2e:0370:7334")
    assert_equal uri.to_s, "http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]"
    uri = ActionDispatch::Http::URI.build_from_faulty_string(":")
    assert_equal uri.to_s, ""
  end

  test "extract domain and subdomains" do
    uri = ActionDispatch::Http::URI.build_from_string("http://sub.do.main.app.test/")
    assert_equal "sub.do.main", uri.subdomain
    assert_equal "sub.do", uri.subdomain(2)
    assert_equal "sub", uri.subdomain(3)
    assert_equal %w(sub do main), uri.subdomains
    assert_equal %w(sub), uri.subdomains(3)

    assert_equal "app.test", uri.domain
    assert_equal "main.app.test", uri.domain(2)
  end
end
