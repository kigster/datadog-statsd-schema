# frozen_string_literal: true

# vim: ft=ruby

namespace "marathon" do
  tags do
    tag :course, values: %w[sf-marathon new-york austin]
    tag :length, values: %w[full half]
  end

  namespace "started" do
    metrics do
      counter "total" do
        description "Number of people who started the Marathon"
        tags required: %i[course length]
      end
    end
  end

  namespace "finished" do
    metrics do
      counter "total" do
        description "Number of people who finished the Marathon"
        inherit_tags "marathon.started.total"
      end

      distribution "duration" do
        description "Marathon duration"
        inherit_tags "marathon.started.total"
      end
    end
  end
end
