Feature: Wiki
  In order to share content on wiki
  A user
  Should be able to create and manage wiki pages

  Background:
    Given I am logged in

  Scenario: Logged user visits a fresh wiki and creates first page
    Then I should see "Page does not exists. Do you want to create it?"
    And I create "/" page with title "Hello world" body "Hello universe"
    Then I should see "Page successfully created."
    And I should see "Hello world"
    And I should see "Hello universe"

  Scenario: User wants to edit a page he created
    When I create "/" page with title "Hello world" body "Hello universe"
    And I edit "/" page with title "Changed title" body "Changed body"
    Then I should see "Page successfully updated."
    And I should see "Changed body"

  Scenario: User wants to create a wiki page without existing parent
    When I go to a page without parent
    Then I should see "Parent page does not exists."

  Scenario: User uses markdown syntax on wiki page
    When I create "/" page with title "Markdown Page" body "Text with *emphasis*."
    Then I should see "emphasis" within "em"

  Scenario: User wants to go to page without slash
    When I create "/" page
    And I create "/nested" page with address in body
    Then I should see "Address: /nested/"
    
  