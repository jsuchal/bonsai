Feature: Wiki
  In order to share rss data
  A user
  Should be able to see rss changes

  Background:
    Given I am logged in
   
  Scenario: check if RSS feeds from page menu works properly
    When I create "/" page with title "Root page"
    And I follow "RSS feed of page changes"
    Then I should see "Root page changes"

  Scenario: check if RSS feed of page changes from page menu works properly without login
      When I create "/" page with title "Root page"
      And I follow "RSS feed of page changes"
      Then I should see "Root page changes"
      When I go to the main page
      And I follow "Log out"
      And I follow "RSS feed of page changes"
      Then I should see "Root page changes"

  Scenario: check if RSS works properly
    When I create "/" page with title "Root page"
    And I follow "RSS feed of page changes"
    Then I should see "Root page changes"
    When I go to the main page
    And I edit "/" page with title "Some NEW title"
    And I follow "RSS feed of page changes"
    Then I should see "Some NEW title changes"

  Scenario: check if user who has not permission can not see RSS
    Given user "johno" exists
    And user "matell" exists
    And I am not logged in
    When I go to the main page
    And I login as "matell"
    And I create "/" page
    And I follow "RSS feed of page changes"
    Then I should see "Some title changes"
    When I go to the main page
    And page "/" is viewable by "matell"
    And I logout
    And I login as "johno"
    And I should not see "RSS feed of page changes"
    When I go to /?rss
    Then I should not see "Some title changes"

  Scenario: check link on diff in rss feeds
    Given I am not logged in
    And that a "main" page with multiple revisions exist
    And I am logged in
    And I follow "RSS feed of page changes"
    And I should see ";diff?first_revision=0&second_revision=1"
    And I go to /;diff?first_revision=0&second_revision=1
    Then I should see "Diff for main"

    