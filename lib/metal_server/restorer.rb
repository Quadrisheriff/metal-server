# frozen_string_literal: true

#==============================================================================
# Copyright (C) 2019-present Alces Flight Ltd.
#
# This file is part of Metal Server.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Metal Server is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Cloud. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Metal Server, please visit:
# https://github.com/openflighthpc/metal-server
#===============================================================================

require 'tmpdir'

module MetalServer
  class RestorerBusyError < Sinja::HttpError
    def self.raise_busy_dir(base)
      msg = <<~MESSAGE.squish
        Can not continue as a directory is currently locked by an update. This is
        likely due to a concurrent request and will be available soon. Please
        try again later.
      MESSAGE
      msg += ("\n\n" + <<~MESSAGE.squish)
        If this error persists, please contact your system administrator for further
        assistance.
      MESSAGE
      msg += ("\n\n" + <<~MESSAGE.squish)
        The following directory is currently busy:
        #{base}
      MESSAGE
      raise self, msg
    end

    def initialize(*a)
      super(503, *a)
    end
  end

  class Restorer
    include FlightConfig::Updater

    def self.backup_multiple(*inputs_dirs, &b)
      dirs = inputs_dirs.dup
      if dirs.empty?
        b.call if b
      else
        backup_and_restore_on_error(dirs.pop) do
          backup_multiple(*dirs, &b)
        end
      end
    end

    def self.backup_and_restore_on_error(base)
      # Tries to create a new restorer as this prevents multiple running at the same time
      begin
        create(base)
      rescue FlightConfig::CreateError
        RestorerBusyError.raise_busy_dir(base)
      end.tap do |restorer|
        begin
          # Set the base paths
          base_dir = restorer.base
          base_tmp_dir = Dir.mktmpdir(File.dirname(base_dir))

          # Ensures the directory exists
          FileUtils.mkdir_p(base_dir)

          # Copy the original files to the temporary directory
          Dir.each_child(base_dir) do |name|
            FileUtils.cp_r(File.expand_path(name, base_dir), base_tmp_dir)
          end

          # Yield control to the updater to preform the system commands
          yield if block_given?

          # Remove the temporary directory on success
          FileUtils.rm_rf base_tmp_dir
        ensure
          # Restore from the temporary directory if it still exists
          # This indicates something went wrong and works with Interrupt
          if Dir.exists?(base_tmp_dir)
            FileUtils.rm_rf base_dir
            FileUtils.mkdir_p base_dir

            Dir.each_child(base_tmp_dir) do |tmp|
              FileUtils.mv File.expand_path(tmp, base_tmp_dir), base_dir
            end

            FileUtils.rmdir base_tmp_dir
          end

          # Ensure the restorer object clears it self
          FileUtils.rm_f restorer.path
        end
      end
    end

    def self.path(base)
      "#{base.chomp('/')}.restorer.yaml"
    end

    def base
      __inputs__[0]
    end
  end
end

