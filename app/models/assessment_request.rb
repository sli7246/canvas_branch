#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

class AssessmentRequest < ActiveRecord::Base
  include Workflow
  attr_accessible :rubric_assessment, :user, :asset, :assessor_asset, :comments, :rubric_association, :assessor
  belongs_to :user
  belongs_to :asset, :polymorphic => true
  belongs_to :assessor_asset, :polymorphic => true
  belongs_to :assessor, :class_name => 'User'
  belongs_to :submission, :foreign_key => 'asset_id'
  belongs_to :rubric_association
  has_many :submission_comments
  belongs_to :rubric_assessment
  validates_length_of :comments, :maximum => maximum_text_length, :allow_nil => true, :allow_blank => true
  
  before_save :infer_uuid
  has_a_broadcast_policy
  
  def infer_uuid
    self.uuid ||= AutoHandle.generate_securish_uuid
  end
  protected :infer_uuid
  
  set_broadcast_policy do |p|
    p.dispatch :rubric_assessment_submission_reminder
    p.to { self.user }
    p.whenever {|record|
      record.assigned? && (!record.just_created || (@send_reminder && !@send_invitation))
    }

    p.dispatch :rubric_assessment_invitation
    p.to { self.assessor }
    p.whenever {|record|
      record.assigned? && (record.just_created || @send_invitation)
    }
  end
  
  named_scope :incomplete, lambda {
    {:conditions => ['assessment_requests.workflow_state = ?', 'assigned'] }
  }
  named_scope :for_assessee, lambda{|user_id|
    {:conditions => ['assessment_requests.user_id = ?', user_id]}
  }

  def send_invitation!
    @send_invitation = true
    self.save!
    @send_invitation = nil
    true
  end
  
  def send_reminder!
    @send_reminder = true
    self.updated_at = Time.now
    self.save!
    @send_reminder = nil
    true
  end

  def context
    submission.try(:context)
  end
  
  def assessor_name
    self.rubric_assessment.assessor_name rescue ((self.assessor.name rescue nil) || t("#unknown", "Unknown"))
  end
  
  workflow do
    state :assigned do
      event :complete, :transitions_to => :completed
    end
    
    # assessment request now has rubric_assessment
    state :completed
  end
  
  def asset_title
    (self.asset.assignment.title rescue self.asset.title) rescue t("#unknown", "Unknown")
  end
  
  def comment_added(comment)
    self.workflow_state = "completed" unless self.rubric_association && self.rubric_association.rubric
  end
  
  def asset_user_name
    self.asset.user.name rescue t("#unknown", "Unknown")
  end
  
  def asset_context_name
    (self.asset.context.name rescue self.asset.assignment.context.name) rescue t("#unknown", "Unknown")
  end
  
  def self.serialization_excludes; [:uuid]; end
end
