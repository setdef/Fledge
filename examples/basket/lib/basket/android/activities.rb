# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "java"

module Basket
  module Android
    # The Application and the Activity that Android made before Basket's
    # Ruby started. A view needs a Context, and Android gives one only to
    # the components it creates, so a program Android did not start
    # through a Java class of its own has to ask Android's runtime for it.
    #
    # Android has no public way to do that, so Activities reads four
    # members of android.app.ActivityThread, which Android lists as
    # unsupported: they work for every app today, and a later Android may
    # take them away. The public Application.registerActivityLifecycleCallbacks
    # then reports every Activity Android makes afterwards.
    module Activities
      # The class that holds the app's Application and its Activities.
      THREAD = "android.app.ActivityThread"

      class << self
        # The app's Application, a Context that lives as long as the app.
        def application
          Java::Klass[THREAD].currentApplication
        end

        # The Activity Android made first, the one whose screen the person
        # sees when Ruby starts.
        def first
          activities = Java::Klass[THREAD].currentActivityThread.field("mActivities", "Landroid/util/ArrayMap;")
          raise Java::Error, "Android has made no Activity" if activities.size.zero?

          activities.valueAt(0).field("activity", "Landroid/app/Activity;")
        end
      end
    end
  end
end
