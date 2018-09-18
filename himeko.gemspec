
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "himeko/version"

Gem::Specification.new do |spec|
  spec.name          = "himeko"
  spec.version       = Himeko::VERSION
  spec.authors       = ["Sorah Fukumori"]
  spec.email         = ["sorah@cookpad.com"]

  spec.summary       = %q{AWS IAM access key self service & management console federated login}
  spec.homepage      = "https://github.com/sorah/himeko"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-core" # aws-sdk-sts
  spec.add_dependency "aws-sdk-iam"
  spec.add_dependency "aws-sdk-dynamodb"

  spec.add_dependency "sinatra"
  spec.add_dependency "rack-protection"
  spec.add_dependency "erubi"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0"
end
