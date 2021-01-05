#
# Copyright 2012-2014 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
name "chef"
default_version "local_source"

license "Apache-2.0"
license_file "LICENSE"

# Grab accompanying notice file.
# So that Open4/deep_merge/diff-lcs disclaimers are present in Omnibus LICENSES tree.
license_file "NOTICE"

# For the specific super-special version "local_source", build the source from
# the local git checkout. This is what you'd want to occur by default if you
# just ran omnibus build locally.
version("local_source") do
  source path: "#{project.files_path}/../..",
         # Since we are using the local repo, we try to not copy any files
         # that are generated in the process of bundle installing omnibus.
         # If the install steps are well-behaved, this should not matter
         # since we only perform bundle and gem installs from the
         # omnibus cache source directory, but we do this regardless
         # to maintain consistency between what a local build sees and
         # what a github based build will see.
         options: { exclude: [ "omnibus/vendor" ] }
end

# For any version other than "local_source", fetch from github.
# This is the behavior the transitive omnibus software deps such as chef-dk
# expect.
if version != "local_source"
  source git: "https://github.com/chef/chef.git"
end

relative_path "chef"

if windows?
  dependency "ruby-windows"
  dependency "openssl-windows"
  dependency "ruby-windows-devkit"
  dependency "ruby-windows-devkit-bash"
  dependency "cacerts"
else
  dependency "ruby"
  dependency "libffi"
end

dependency "rubygems"
dependency "bundler"
dependency "ohai"
dependency "appbundler"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  bundle "install --without #{excluded_groups.join(" ")}", env: env

  # ensure we put the gems in the right place to get picked up by the publish scripts
  delete "pkg"
  mkdir "pkg"
  copy "chef*.gem", "pkg"
  
  if windows?
    # Normally we would symlink the required unix tools.
    # However with the introduction of git-cache to speed up omnibus builds,
    # we can't do that anymore since git on windows doesn't support symlinks.
    # https://groups.google.com/forum/#!topic/msysgit/arTTH5GmHRk
    # Therefore we copy the tools to the necessary places.
    # We need tar for 'knife cookbook site install' to function correctly
    {
      'tar.exe'          => 'bsdtar.exe',
      'libarchive-2.dll' => 'libarchive-2.dll',
      'libexpat-1.dll'   => 'libexpat-1.dll',
      'liblzma-1.dll'    => 'liblzma-1.dll',
      'libbz2-2.dll'     => 'libbz2-2.dll',
      'libz-1.dll'       => 'libz-1.dll',
    }.each do |target, to|
      copy "#{install_dir}/embedded/mingw/bin/#{to}", "#{install_dir}/bin/#{target}"
    end
  end
  
  # use the rake install task to build/install chef-config/chef-utils
  bundle "exec rake install", env: env

  # install the whole bundle first
  bundle "install --without server docgen", env: env

  gemspec_name = windows? ? 'chef-windows.gemspec' : 'chef.gemspec'

  # This step will build native components as needed - the event log dll is
  # generated as part of this step.  This is why we need devkit.
  gem "build #{gemspec_name}", env: env

  # Don't use -n #{install_dir}/bin. Appbundler will take care of them later
  gem "install chef*.gem " \
      " --no-ri --no-rdoc" \
      " --verbose", env: env

  # Always deploy the powershell modules in the correct place.
  if windows?
    mkdir "#{install_dir}/modules/chef"
    copy "distro/powershell/chef/*", "#{install_dir}/modules/chef"
  end

  auxiliary_gems = {}
  auxiliary_gems['ruby-shadow'] = '>= 0.0.0' unless aix? || windows?

  auxiliary_gems.each do |name, version|
    gem "install #{name}" \
        " --version '#{version}'" \
        " --no-ri --no-rdoc" \
        " --verbose", env: env
  end

  appbundle 'chef'
  appbundle 'ohai'

  # Clean up
  delete "#{install_dir}/embedded/docs"
  delete "#{install_dir}/embedded/share/man"
  delete "#{install_dir}/embedded/share/doc"
  delete "#{install_dir}/embedded/share/gtk-doc"
  delete "#{install_dir}/embedded/ssl/man"
  delete "#{install_dir}/embedded/man"
  delete "#{install_dir}/embedded/info"
end
