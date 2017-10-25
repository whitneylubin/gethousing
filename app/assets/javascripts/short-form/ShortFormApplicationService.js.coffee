ShortFormApplicationService = (
  $translate, $http, $state, uuid,
  ListingService, ShortFormDataService, AddressValidationService, GeocodingService,
  AnalyticsService, FileUploadService
) ->
  Service = {}
  Service.listing = ListingService.listing
  Service.form = {}
  Service.accountApplication = {}
  Service.application = {}
  Service._householdEligibility = {}
  Service.activeSection = {}
  emptyAddress = { address1: null, address2: "", city: null, state: null, zip: null }
  Service.applicationDefaults =
    id: null
    lotteryNumber: null
    status: 'draft'
    applicationSubmittedDate: null
    surveyComplete: false
    answeredCommunityScreening: null
    applicationSubmissionType: 'Electronic'
    applicant:
      id: 1
      home_address: angular.copy(emptyAddress)
      phone: null
      mailing_address: angular.copy(emptyAddress)
      terms: {}
    alternateContact:
      mailing_address: angular.copy(emptyAddress)
    householdMembers: []
    preferences:
      liveInSf: null
      workInSf: null
      liveWorkInSf: null
      antiDisplacement: null
      neighborhoodResidence: null
      assistedHousing: null
      rentBurden: null
      optOut: {}
      documents:
        rentBurden: {}
    householdIncome:
      incomeTotal: null
      incomeTimeframe: null
    groupedHouseholdAddresses: []
    adaPrioritiesSelected: {}
    completedSections:
      Intro: false
      You: false
      Household: false
      Income: false
      Preferences: false
    # as you proceed through each page, validatedForms will store:
    #  [pagename]: T/F
    # to indicate if that form was left valid or invalid
    validatedForms:
      You: {}
      Household: {}
      Income: {}
      Preferences: {}
      Review: {}
    # for storing last page of your draft, to return to. default to first page
    lastPage: 'dahlia.short-form-application.name'

  Service.currentRentBurdenAddress = {}
  Service.current_id = 1
  Service.refreshSessionUid = ->
    Service.session_uid = "#{uuid.v4()}-#{uuid.v4()}"
  Service.refreshSessionUid()

  ## initialize other related services
  Service.initServices = ->
    # initialize FileUploadService to have access to preferences / session_uid
    FileUploadService.preferences = Service.preferences
    FileUploadService.session_uid = ->
      Service.session_uid
    ShortFormDataService.defaultCompletedSections = Service.applicationDefaults.completedSections
  ## -------

  Service.resetUserData = (data = {}) ->
    application = _.merge({}, Service.applicationDefaults, data)
    angular.copy(application, Service.application)
    Service.applicant = Service.application.applicant
    Service.preferences = Service.application.preferences
    Service.alternateContact = Service.application.alternateContact
    Service.householdMember = {}
    Service.householdMembers = Service.application.householdMembers
    Service.initServices()

  Service.resetUserData()
  # --- end initialization

  Service.inputInvalid = (fieldName, form = Service.form.applicationForm, identifier) ->
    return false unless form
    fieldName = if identifier then "#{identifier}_#{fieldName}" else fieldName
    field = form[fieldName]
    if form && field
      field.$invalid && (field.$touched || form.$submitted)
    else
      false

  Service.completeSection = (section) ->
    Service.application.completedSections[section] = true

  Service.userCanAccessSection = (name, state = null) ->
    # user can't access later sections yet when on the welcome page
    if state and (Service.isWelcomePage(state))
      return false

    completed = Service.application.completedSections
    validated = Service.application.validatedForms
    switch name
      when 'You'
        true
      when 'Household'
        completed.Intro &&
        completed.You &&
        # make sure all validatedForms in previous section == true
        _.every(validated['You'], (i) -> i)
      when 'Income'
        Service.userCanAccessSection('Household') &&
        completed.Household &&
        # make sure all validatedForms in previous section == true
        _.every(validated['Household'], (i) -> i)
      when 'Preferences'
        Service.userCanAccessSection('Income') &&
        completed.Income &&
        # make sure all validatedForms in previous section == true
        _.every(validated['Income'], (i) -> i)
      when 'Review'
        Service.userCanAccessSection('Preferences') &&
        completed.Preferences &&
        # make sure all validatedForms in previous section == true
        _.every(validated['Preferences'], (i) -> i)
      else
        false

  Service.storeLastPage = (stateName) ->
    lastPage = _.replace(stateName, 'dahlia.short-form-application.', '')
    # don't save the fact that we landed on "choose-xxx" pages
    return if _.includes(['choose-draft', 'choose-account-settings'], lastPage)
    Service.application.lastPage = lastPage

  Service.copyHomeToMailingAddress = ->
    unless Service.applicant.hasAltMailingAddress
      angular.copy(Service.applicant.home_address, Service.applicant.mailing_address)

  Service.validMailingAddress = ->
    !! (Service.applicant.mailing_address.address1 &&
        Service.applicant.mailing_address.city &&
        Service.applicant.mailing_address.state &&
        Service.applicant.mailing_address.zip)

  Service.clearPhoneData = (type) ->
    if type == 'alternate'
      Service.applicant.noPhone = false
      Service.applicant.alternatePhone = null
      Service.applicant.alternatePhoneType = null
    else if type == 'phone'
      Service.applicant.additionalPhone = false
      Service.applicant.phone = null
      Service.applicant.phoneType = null

  Service.clearAlternateContactDetails = ->
    clearedData = { alternateContactType: 'None' }
    validated = Service.application.validatedForms.You
    delete validated['alternate-contact-name']
    delete validated['alternate-contact-phone-address']
    angular.copy(clearedData, Service.application.alternateContact)

  Service._nextId = ->
    if Service.householdMembers.length > 0
      max_id = _.maxBy(Service.householdMembers, 'id').id
    else
      max_id = Service.current_id
    Service.current_id = max_id + 1

  Service.addHouseholdMember = (householdMember) ->
    if householdMember.hasSameAddressAsApplicant == 'Yes'
      # copy applicant's preferenceAddressMatch to householdMember
      householdMember.preferenceAddressMatch = Service.applicant.preferenceAddressMatch
    if !householdMember.id
      householdMember.id = Service._nextId()
      Service.householdMembers.push(angular.copy(householdMember))
    else
      # update existing householdMember
      householdMemberToUpdate = _.find(Service.householdMembers, {id: householdMember.id})
      angular.copy(householdMember, householdMemberToUpdate)
    Service.invalidateHouseholdForm()

  Service.resetHouseholdMember = ->
    angular.copy({}, Service.householdMember)

  Service.getHouseholdMember = (id) ->
    angular.copy(_.find(Service.householdMembers, {id: parseInt(id)}), Service.householdMember)

  Service.cancelHouseholdMember = ->
    # list of all householdMembers minus the cancelled one
    householdMembers = Service.householdMembers.filter (m) ->
      (m != Service.householdMember && m.id != Service.householdMember.id)
    # search through all xxx_household_member items in preferences marked for this member
    _.each Service.preferences, (v,k) ->
      if k.indexOf('_household_member') > 0 and v == Service.householdMember.id
        preference = k.split('_household_member')[0]
        Service.cancelPreference(preference)

    # persist the changes to Service.householdMembers
    Service.resetHouseholdMember()
    angular.copy(householdMembers, Service.householdMembers)
    Service.invalidateHouseholdForm()

  Service.copyNeighborhoodMatchToHousehold = ->
    Service.householdMembers.forEach( (member) ->
      if member.hasSameAddressAsApplicant == 'Yes'
        # copy applicant's preferenceAddressMatch to householdMember
        member.preferenceAddressMatch = Service.applicant.preferenceAddressMatch
    )


  # this function sets up Service.groupedHouseholdAddresses which is used by Rent Burden preference
  # - gets called onEnter of household-monthly-rent
  # - it's used to setup the monthly-rent page as well as rent-burden-preference pages
  # - it will reset the addresses and Rent Burden if any members/addresses have changed
  Service.groupHouseholdAddresses = ->
    groupedAddresses = []
    groupedAddress = {}

    primaryAddress = Service.applicant.home_address.address1
    primaryAddress += ' ' + Service.applicant.home_address.address2 if Service.applicant.home_address.address2
    groupedAddress.address = primaryAddress
    primaryApplicant =
      fullName: "#{Service.applicant.firstName} #{Service.applicant.lastName} (You)"
      firstName: "You"
    groupedAddress.members = [primaryApplicant]
    groupedAddresses.push(angular.copy(groupedAddress))

    _.each Service.householdMembers, (member) ->
      groupedAddress = {}
      if member.hasSameAddressAsApplicant == 'Yes'
        groupedAddress.address = primaryAddress
      else
        groupedAddress.address = member.home_address.address1
        groupedAddress.address += ' ' + member.home_address.address2 if member.home_address.address2
      matchedIndex = _.findIndex(groupedAddresses, { address: groupedAddress.address})
      name =
        fullName: "#{member.firstName} #{member.lastName}"
        firstName: member.firstName
      if matchedIndex > -1
        groupedAddresses[matchedIndex].members.push(name)
      else
        groupedAddress.members = [name]
        groupedAddresses.push(angular.copy(groupedAddress))

    _.each groupedAddresses, (groupedAddress) ->
      ShortFormDataService.initRentBurdenDocs(groupedAddress.address, Service.application)
      matchedIndex = _.findIndex(Service.application.groupedHouseholdAddresses, { address: groupedAddress.address})
      if matchedIndex > -1
        groupedAddress.monthlyRent = Service.application.groupedHouseholdAddresses[matchedIndex].monthlyRent
        groupedAddress.dontPayRent = Service.application.groupedHouseholdAddresses[matchedIndex].dontPayRent

    newAddrs = groupedAddresses
    oldAddrs = Service.application.groupedHouseholdAddresses
    if newAddrs.length != oldAddrs.length
      changed = true
    else
      diff = _.differenceWith newAddrs, oldAddrs, (newAddr, oldAddr) ->
        _.isEqual(newAddr.members, oldAddr.members) && newAddr.address == oldAddr.address
      changed = !!diff.length

    if changed # have you changed anything?
      Service.resetPreference('rentBurden')
      angular.copy(groupedAddresses, Service.application.groupedHouseholdAddresses)

  Service.setRentBurdenAddressIndex = (index) ->
    angular.copy(Service.application.groupedHouseholdAddresses[index], Service.currentRentBurdenAddress)
    Service.currentRentBurdenAddress.index = index

  Service.cancelPreference = (preference) ->
    if _.includes(['neighborhoodResidence', 'antiDisplacement'], preference)
      # cancelling Neighborhood also cancels liveInSf
      Service.cancelPreference('liveInSf')
    if _.includes(['liveWorkInSf', 'liveInSf', 'workInSf'], preference)
      # cancels liveWork combo options
      Service.preferences.liveWorkInSf = false
      Service.preferences.liveWorkInSf_preference = null
    if preference == 'liveWorkInSf'
      # cancels both live and work individual options
      Service.unsetPreferenceFields('liveInSf')
      Service.unsetPreferenceFields('workInSf')
    else
      # default, unset the indicated preference
      Service.unsetPreferenceFields(preference)

  Service.unsetPreferenceFields = (preference) ->
    # clear out all fields for this preference
    Service.preferences[preference] = null
    if preference == 'rentBurden'
      FileUploadService.deleteRentBurdenPreferenceFiles(Service.listing.Id)
    else
      Service.preferences["#{preference}_household_member"] = null
      Service.preferences["#{preference}_proofOption"] = null
      FileUploadService.deletePreferenceFile(preference, Service.listing.Id)
      if preference == 'certOfPreference' || preference == 'displaced'
        Service.preferences["#{preference}_certificateNumber"] = null

  Service.cancelOptOut = (preference) ->
    Service.application.preferences.optOut[preference] = false
    if preference == 'neighborhoodResidence'
      # if we cancel our NRHP Opt Out, we cancel liveWorkOptOut as well
      Service.cancelOptOut('liveWorkInSf')

  Service.preferenceRequired = (preference) ->
    # pref is required if we are NOT opted out
    !Service.preferences.optOut[preference]

  Service.setFormPreferenceType = (preference) ->
    if preference == 'liveWorkInSf'
      Service.form.currentPreferenceType = Service.liveWorkPreferenceType()
    else
      Service.form.currentPreferenceType = preference

  Service.showPreference = (preference) ->
    return false unless Service.listingHasPreference(preference)
    switch preference
      when 'liveWorkInSf'
        Service.workInSfMembers().length > 0 && Service.liveInSfMembers().length > 0
      when 'liveInSf'
        Service.liveInSfMembers().length > 0 && Service.workInSfMembers().length == 0
      when 'workInSf'
        Service.workInSfMembers().length > 0 && Service.liveInSfMembers().length == 0
      else
        true

  Service.liveWorkPreferenceType = ->
    if Service.showPreference('liveWorkInSf')
      'liveWorkInSf'
    else if Service.showPreference('liveInSf')
      'liveInSf'
    else
      'workInSf'

  Service.checkHouseholdEligiblity = (listing) ->
    params =
      listing_id: listing.Id,
      eligibility:
        householdsize: Service.householdSize()
        incomelevel: Service.calculateHouseholdIncome()
        childrenUnder6: Service._childrenUnder6()
    $http.post("/api/v1/short-form/validate-household", params).success((data, status, headers, config) ->
      # assigning value to object for now to make function unit testable
      angular.copy(data, Service._householdEligibility)
      return Service.householdEligibility
    )

  Service.hasCompleteRentBurdenFiles = ->
    _.every Service.application.groupedHouseholdAddresses, (groupedAddress) ->
      Service.hasCompleteRentBurdenFilesForAddress(groupedAddress.address)

  Service.hasCompleteRentBurdenFilesForAddress = (address) ->
    files = Service.application.preferences.documents.rentBurden[address]
    return false unless files
    files.lease.file && _.some(_.map(files.rent, 'file'))

  Service.householdSize = ->
    Service.application.householdMembers.length + 1

  Service._childrenUnder6 = ->
    allMembers = angular.copy(Service.application.householdMembers)
    allMembers.push(Service.applicant)
    _.reduce(allMembers, (count, member) ->
      dob = "#{member.dob_year}-#{member.dob_month}-#{member.dob_day}"
      dob = moment(dob, 'YYYY-MM-DD')
      age = moment().diff(dob, 'years')
      count + (if age < 6 then 1 else 0)
    , 0)

  Service.calculateHouseholdIncome = ->
    income = Service.application.householdIncome || 0
    if income.incomeTimeframe == 'per_year'
      income.incomeTotal
    else if income.incomeTimeframe == 'per_month'
      income.incomeTotal * 12

  Service.clearAddressRelatedProofForMember = (member) ->
    addressPreferences = [ 'liveInSf', 'neighborhoodResidence', 'antiDisplacement' ]
    addressPreferences.forEach (preference) ->
      selectedMember = Service.preferences[preference + '_household_member']
      if member.id == selectedMember
        FileUploadService.deletePreferenceFile(preference, Service.listing.Id)

  # update lists of eligible people for the dropdowns for these preferences
  Service.refreshPreferences = (type = 'all') ->
    if type == 'liveWorkInSf' || type == 'all'
      Service._updatePreference('liveInSf', Service.liveInSfMembers())
      Service._updatePreference('workInSf', Service.workInSfMembers())
    else if type == 'workInSf'
      Service._updatePreference('workInSf', Service.workInSfMembers())
    if type == 'neighborhoodResidence' || type == 'all'
      Service._updatePreference('neighborhoodResidence', Service.liveInTheNeighborhoodMembers())
    if type == 'antiDisplacement' || type == 'all'
      Service._updatePreference('antiDisplacement', Service.liveInTheNeighborhoodMembers())

  Service.eligibleMembers = (preference) ->
    switch preference
      when 'liveInSf'
        Service.liveInSfMembers()
      when 'workInSf'
        Service.workInSfMembers()
      when 'neighborhoodResidence', 'antiDisplacement'
        Service.liveInTheNeighborhoodMembers()
      else
        Service.fullHousehold()

  Service.liveInSfMembers = ->
    applicantLivesInSf = _.lowerCase(Service.applicant.home_address.city) == 'san francisco'
    liveInSfMembers = Service.application.householdMembers.filter (member) ->
      if member.hasSameAddressAsApplicant == 'No'
        _.lowerCase(member.home_address.city) == 'san francisco'
      else
        member.hasSameAddressAsApplicant == 'Yes' && applicantLivesInSf
    liveInSfMembers.unshift(Service.applicant) if applicantLivesInSf
    return liveInSfMembers

  Service.workInSfMembers = ->
    Service.fullHousehold().filter (member) ->
      member.workInSf == 'Yes'

  Service.liveInTheNeighborhoodMembers = ->
    # used by both NRHP / ADHP
    Service.fullHousehold().filter (member) ->
      # find all household members that match NRHP
      member.preferenceAddressMatch == 'Matched'

  Service.fullHousehold = ->
    # return an array with the Household and Primary Applicant
    # JS concat creates a new array (does not modify HH member array)
    Service.application.householdMembers.concat([Service.applicant])

  Service.memberAge = (member) ->
    dob = moment("#{member.dob_year}-#{member.dob_month}-#{member.dob_day}", 'YYYY-MM-DD')
    age = moment().diff(dob, 'years')
    age

  Service.maxHouseholdAge = ->
    _.max(_.map(Service.fullHousehold(), Service.memberAge))

  Service.listingHasPreference = (preference) ->
    ListingService.hasPreference(preference)

  Service.listingHasNRHP_or_ADHP = ->
    Service.listingHasPreference('neighborhoodResidence') || Service.listingHasPreference('antiDisplacement')

  Service.eligibleForLiveWork = ->
    return false unless Service.listingHasPreference('liveWorkInSf')
    liveInSfEligible = Service.liveInSfMembers().length > 0
    workInSfEligible = Service.workInSfMembers().length > 0
    return (liveInSfEligible || workInSfEligible)

  Service.eligibleForNRHP = ->
    return false unless Service.listingHasPreference('neighborhoodResidence')
    Service.liveInTheNeighborhoodMembers().length > 0

  Service.eligibleForADHP = ->
    return false unless Service.listingHasPreference('antiDisplacement')
    Service.liveInTheNeighborhoodMembers().length > 0

  Service.eligibleForAssistedHousing = ->
    return false unless Service.listingHasPreference('assistedHousing')
    Service.application.hasPublicHousing == 'Yes'

  Service.eligibleForRentBurden = ->
    return false unless Service.listingHasPreference('rentBurden')
    totalMonthlyRent = _.sumBy(Service.application.groupedHouseholdAddresses, 'monthlyRent')
    incomeTotal = parseFloat(Service.application.householdIncome.incomeTotal)
    if Service.application.householdIncome.incomeTimeframe == 'per_month'
      ratio = totalMonthlyRent / incomeTotal
    else
      ratio = (totalMonthlyRent * 12) / incomeTotal
    # must have answered "No" and rent > 50% of income
    Service.application.hasPublicHousing == 'No' && ratio >= .5

  Service.applicantHasNoPreferences = ->
    # true if no preferences are selected at all
    prefList = ShortFormDataService.preferences
    customPrefs = _.map(Service.listing.customPreferences, 'listingPreferenceID')
    prefList = prefList.concat(customPrefs)
    return !_.some(_.pick(Service.preferences, prefList))

  Service.claimedCustomPreference = (preference) ->
    Service.applicationHasPreference(preference.listingPreferenceID)

  Service.applicationHasPreference = (preference) ->
    !! Service.preferences[preference]

  Service.copyNeighborhoodToLiveInSf = (preference) ->
    # preference is either neighborhoodResidence or antiDisplacement
    # clear out any previously entered values for live/work
    Service.cancelPreference('workInSf')
    # reset the form so it's not in an "invalid" state
    Service.resetLiveWorkForm()
    # copy Neighborhood values to liveInSf
    neighborhoodMember = Service.preferences["#{preference}_household_member"]
    proofOption = Service.preferences["#{preference}_proofOption"]
    # copy e.g. "Water Bill" so that it shows up properly on the review screen
    proofOption = Service.preferences.documents[preference].proofOption
    file = Service.preferences.documents[preference].file
    Service.preferences.liveInSf = true
    Service.preferences.liveInSf_household_member = neighborhoodMember
    Service.preferences.liveInSf_proofOption = proofOption
    Service.preferences.documents.liveInSf = {proofOption: proofOption}

  Service._updatePreference = (preference, eligibleMembers) ->
    # only check to reset this preference if it has been selected
    return unless Service.preferences[preference]
    members = eligibleMembers.map (member) -> member.id
    selectedMember = Service.preferences[preference + '_household_member']
    # if selected member's eligibility is changed, invalidate form, cancel preference and force user to review again
    if _.isEmpty(members) || selectedMember && !_.includes(members, selectedMember)
      Service.resetPreference(preference)

  Service.resetPreference = (preference) ->
    # this should be called when you're cancelling the preference from an external factor
    # e.g. you changed your address and are no longer eligible for liveInSf,
    # so we totally cancel liveInSf and reset the preference validatedForms
    Service.application.completedSections.Preferences = false
    angular.copy({}, Service.application.validatedForms.Preferences)
    # cancel both preference and optOut, this preference is no longer valid
    Service.cancelPreference(preference)
    Service.cancelOptOut(preference)

  Service.onExit = (e) ->
    AnalyticsService.trackFormAbandon('Application')
    e.returnValue = $translate.instant('T.ARE_YOU_SURE_YOU_WANT_TO_LEAVE')

  Service.isWelcomePage = (state) ->
    !!state.name.match(/short-form-welcome\./)

  Service._isPrimaryOrHouseholdAddressPage = (state) ->
    stateName = state.name.replace(/dahlia.short-form-(welcome|application)\./, "")
    stateName.match(/contact/) || stateName.match(/household-member-form/)

  Service.isShortFormPage = (state) ->
    !!state.name.match(/short-form-application\./)

  Service.sendToLastPageofApp = (toState) ->
    appLastPage = Service.application.lastPage
    if toState.name != "dahlia.short-form-application.#{appLastPage}" &&
      $state.href("dahlia.short-form-application.#{appLastPage}")
        $state.go("dahlia.short-form-application.#{appLastPage}")

  Service.checkFormState = (stateName, section) ->
    if Service.form.applicationForm
      stateName = stateName.replace(/dahlia.short-form-(welcome|application)\./, "")
      # special case for household-member-form
      return if stateName.match(/household-member-form/)
      # special case for rentBurden subpages
      return if stateName.match(/rent-burden-preference-edit/)
      isValid = Service.form.applicationForm.$valid
      # special case for contact form
      if stateName.match(/contact/)
        applicant = Service.applicant
        addressValid = !!applicant.preferenceAddressMatch
        isValid = isValid && addressValid
      Service.application.validatedForms[section.name][stateName] = isValid

  Service.authorizedToProceed = (toState, fromState, toSection) ->
    return true unless toState && fromState
    return false unless Service.userCanAccessSection(toSection.name)
    # they're "jumping ahead" if they're not coming from a short form page or create-account
    # and they're trying to go to a page that's not either the first page, or their stored lastPage
    namePage = 'dahlia.short-form-application.name'
    lastPage = "dahlia.short-form-application.#{Service.application.lastPage}"
    jumpAhead = Service.isShortFormPage(toState) &&
                !Service.isShortFormPage(fromState) &&
                !_.includes([namePage, lastPage], toState.name)
    return !jumpAhead

  Service.isLeavingShortForm = (toState, fromState) ->
    Service.isShortFormPage(fromState) && !Service.isShortFormPage(toState)

  Service.isEnteringShortForm = (toState, fromState) ->
    !Service.isShortFormPage(fromState) && Service.isShortFormPage(toState)

  Service.isLeavingConfirmationToSignIn = (toState, fromState) ->
    fromState.name == 'dahlia.short-form-application.create-account' &&
      toState.name == 'dahlia.sign-in' &&
      Service.application.status.match(/submitted/i)

  Service.isLeavingConfirmation = (toState, fromState) ->
    Service.application.status.match(/submitted/i) &&
      toState.name != 'dahlia.sign-in' &&
      !Service.isShortFormPage(toState) &&
      (fromState.name == 'dahlia.short-form-application.confirmation' ||
      fromState.name == 'dahlia.short-form-application.review-submitted' ||
      fromState.name == 'dahlia.short-form-application.create-account')


  Service.hittingBackFromConfirmation = (fromState, toState) ->
    # going from confirmation to a short form page that ISN'T "create-account" or "review"
    fromState.name == 'dahlia.short-form-application.confirmation' &&
      toState.name != 'dahlia.short-form-application.review-submitted' &&
      toState.name != 'dahlia.short-form-application.create-account' &&
      Service.isShortFormPage(toState)

  Service.invalidateNameForm = ->
    Service.application.validatedForms['You']['name'] = false

  Service.invalidateContactForm = ->
    Service.application.validatedForms['You']['contact'] = false

  Service.invalidateAltContactTypeForm = ->
    Service.application.validatedForms['You']['alternate-contact-type'] = false

  Service.invalidateIncomeForm = ->
    Service.application.completedSections['Income'] = false
    Service.application.validatedForms['Income']['income'] = false

  Service.invalidateHouseholdForm = ->
    Service.application.completedSections['Household'] = false
    Service.application.completedSections['Preferences'] = false
    Service.application.completedSections['Income'] = false

  Service.invalidatePreferencesForm = ->
    Service.application.completedSections['Preferences'] = false

  Service.resetLiveWorkForm = ->
    return unless Service.application.validatedForms['Preferences']
    delete Service.application.validatedForms['Preferences']['live-work-preference']

  Service._resetCompletedSections = ->
    angular.copy(Service.applicationDefaults.completedSections, Service.application.completedSections)

  Service.resetMonthlyRentForm = ->
    return unless Service.application.validatedForms['Household']
    Service.application.groupedHouseholdAddresses = []
    delete Service.application.validatedForms['Household']['household-monthly-rent']

  Service.invalidateMonthlyRentForm = ->
    return unless Service.application.validatedForms['Household']
    Service.application.validatedForms['Household']['household-monthly-rent'] = false

  Service.resetAssistedHousingForm = ->
    Service.cancelPreference('assistedHousing')
    return unless Service.application.validatedForms['Preferences']
    delete Service.application.validatedForms['Preferences']['assisted-housing-preference']

  Service.preferenceFileIsLoading = (fileType) ->
    !! Service.preferences["#{fileType}_loading"]

  Service.invalidateCurrentSectionIfIncomplete = ->
    # this will set the current section "completedSections" to false
    # in the event that you've gone back and edited a form and left it in an invalid state
    section = Service.activeSection
    return unless section && section.name
    isValid = Service.checkFormState($state.current.name, section)
    if !isValid && Service.application.completedSections[section.name]
      Service.application.completedSections[section.name] = false

  Service.submitApplication = (options={}) ->
    if options.finish
      Service.application.status = 'submitted'

    Service.invalidateCurrentSectionIfIncomplete()
    # clean up any old data hanging around from now invalidated/changed preferences
    Service.refreshPreferences()
    Service.application.applicationSubmittedDate = moment().tz('America/Los_Angeles').format('YYYY-MM-DD')
    # this gets stored in the metadata of the application to verify who's trying to "claim" it after submission
    Service.application.session_uid = Service.session_uid
    params =
      application: ShortFormDataService.formatApplication(Service.listing.Id, Service.application)
      uploaded_file:
        session_uid: Service.session_uid

    if options.attachToAccount
      # NOTE: This temp_session_id is vital for the operation of Create Account on "save and finish"
      params.temp_session_id = Service.session_uid

    if params.application.id
      # update
      id = params.application.id
      if options.attachToAccount
        appSubmission = $http.put("/api/v1/short-form/claim-application/#{id}", params)
      else
        appSubmission = $http.put("/api/v1/short-form/application/#{id}", params)
    else
      # create
      appSubmission = $http.post('/api/v1/short-form/application', params)

    appSubmission.success((data, status, headers, config) ->
      if data.lotteryNumber
        Service.application.lotteryNumber = data.lotteryNumber
        Service.application.id = data.id
    ).error( (data, status, headers, config) ->
      # error alert is handled by httpProvider.interceptor in angularProviders
      return
    )

  Service.deleteApplication = (id) ->
    $http.delete("/api/v1/short-form/application/#{id}").success((data, status) ->
      true
    )

  Service.getApplication = (id) ->
    $http.get("/api/v1/short-form/application/#{id}").success((data, status) ->
      Service.loadApplication(data)
    )

  Service.getMyApplicationForListing = (listingId = Service.listing.Id, opts = {}) ->
    autofill = if opts.autofill then '?autofill=true' else ''
    $http.get("/api/v1/short-form/listing-application/#{listingId}#{autofill}").success((data, status) ->
      if opts.forComparison
        Service.loadAccountApplication(data)
      else
        Service.loadApplication(data)
    )

  Service.signInSubmitApplication = (opts = {}) ->
    # check if this user has already applied to this listing
    Service.getMyApplicationForListing(Service.listing.Id, {forComparison: true}).success((data) ->
      if !_.isEmpty(data.application) && Service._previousIsSubmittedOrBothDrafts(data.application)
        # if user already had an application for this listing
        return Service._signInAndSkipSubmit(data.application)
      changed = null
      if Service.application.status.match(/draft/i)
        if opts.type == 'review-sign-in' && Service.hasDifferentInfo(Service.applicant, opts.loggedInUser)
          return $state.go('dahlia.short-form-application.choose-account-settings')
        else
          # make sure short form data inherits logged in user data
          changed = Service.importUserData(opts.loggedInUser)
      Service.submitApplication(opts).then( ->
        opts.submitCallback(changed)
      )
    ).error( ->
      # there was an error retrieving your account info, please try again
      # TODO: add some helpful message to the user
      $state.go('dahlia.short-form-application.name', {id: Service.listing.Id})
    )

  Service._signInAndSkipSubmit = (previousApplication) ->
    if (previousApplication.status.match(/submitted/i))
      # they've already submitted -- send them to "my applications", either with:
      # - alreadySubmitted: "Good news! You already submitted" (if they were trying to save a draft)
      # - doubleSubmit: "You have already submitted to this account" (if they were trying to submit again)
      doubleSubmit = !! Service.application.status.match(/submitted/i)
      $state.go('dahlia.my-applications', {skipConfirm: true, alreadySubmittedId: previousApplication.id, doubleSubmit: doubleSubmit})
    else
      # send them to choose which draft they want to keep
      $state.go('dahlia.short-form-application.choose-draft')

  Service._previousIsSubmittedOrBothDrafts = (previousApplication) ->
    previousApplication.status.match(/submitted/i) || (
      previousApplication.status.match(/draft/i) &&
      Service.application.status.match(/draft/i)
    )


  Service.keepCurrentDraftApplication = (loggedInUser) ->
    Service.importUserData(loggedInUser)
    Service.application.id = Service.accountApplication.id
    # now that we've overridden current application ID with our old one
    # submitApplication() will update our existing draft on salesforce
    Service.submitApplication()

  Service.loadApplication = (data) ->
    formattedApp = {}
    if data.application && !_.isEmpty(data.application)
      files = data.files || []
      if data.application.status.match(/submitted/i) && data.application.listing
        # on submitted app the listing is loaded along with it
        ListingService.loadListing(data.application.listing)
      formattedApp = ShortFormDataService.reformatApplication(data.application, files)
      Service.checkForProofPrefs(formattedApp)

    # pull answeredCommunityScreening from the current session since that Q is answered first
    formattedApp.answeredCommunityScreening ?= Service.application.answeredCommunityScreening

    Service.resetUserData(formattedApp)
    # one last step, reconcile any uploaded files with your saved member + preference data
    Service.refreshPreferences('all')

  Service.checkForProofPrefs = (formattedApp) ->
    proofPrefs = [
      'liveInSf',
      'workInSf',
      'neighborhoodResidence',
      'antiDisplacement',
      'assistedHousing',
    ]
    # make sure all files are present for proof-requiring preferences, otherwise don't let them jump ahead
    _.each proofPrefs, (prefType) ->
      hasPref = formattedApp.preferences[prefType]
      docs = formattedApp.preferences.documents[prefType]
      if hasPref && (_.isEmpty(docs) || _.isEmpty(docs.file))
        formattedApp.completedSections['Preferences'] = false
    if formattedApp.preferences.rentBurden && !Service.hasCompleteRentBurdenFiles()
      formattedApp.completedSections['Preferences'] = false

  Service.loadAccountApplication = (data) ->
    return false if _.isEmpty(data.application)
    formattedApp = ShortFormDataService.reformatApplication(data.application)
    angular.copy(formattedApp, Service.accountApplication)

  Service.checkSurveyComplete = ->
    Service.application.surveyComplete = ShortFormDataService.checkSurveyComplete(Service.applicant)

  Service.importUserData = (loggedInUser) ->
    fields = [
      'email', 'firstName', 'middleName', 'lastName', 'dob_day', 'dob_year', 'dob_month'
    ]
    userData = _.pick(loggedInUser, fields)
    original = angular.copy(Service.applicant)
    # merge the data into applicant
    _.merge Service.applicant, userData
    changed = !_.isEqual(Service.applicant, original)
    Service._mapPrimaryApplicantPreferences(original, userData) if changed
    # return T/F if data was changed or not
    return changed

  Service.hasDifferentInfo = (applicant, loggedInUser) ->
    fields = [
      'email', 'firstName', 'middleName', 'lastName'
    ]
    userData = _.omitBy(_.pick(loggedInUser, fields), _.isNil)
    userData.DOB = ShortFormDataService.formatUserDOB(loggedInUser)
    applicantData = _.omitBy(_.pick(applicant, fields), _.isNil)
    applicantData.DOB = ShortFormDataService.formatUserDOB(applicant)
    !_.isEqual(userData, applicantData)

  Service._mapPrimaryApplicantPreferences = (original, userData) ->
    originalFullName = original.firstName + " " + original.lastName
    _.forEach Service.application.preferences, (value, key) ->
      if value == originalFullName
        Service.application.preferences[key] = userData.firstName + " " + userData.lastName
      return

  ####### Address validation functions
  Service.validateApplicantAddress = (callback) ->
    # validate + geocode address
    # errors are handled in the controller
    afterGeocode = (response) ->
      Service.applicant.geocodingData = response.geocoding_data
      Service.applicant.preferenceAddressMatch = GeocodingService.preferenceAddressMatch
      Service.copyNeighborhoodMatchToHousehold()
      # check if eligibility has changed
      Service.refreshPreferences('all')
      Service.clearAddressRelatedProofForMember(Service.applicant)
      callback()
    AddressValidationService.validate(
      address: Service.applicant.home_address
      type: 'home'
    ).success( ->
      Service.copyHomeToMailingAddress()
      GeocodingService.geocode(
        address: Service.applicant.home_address
        member: Service.applicant
        applicant: Service.applicant
        listing: Service.listing
        has_nrhp_adhp: Service.listingHasNRHP_or_ADHP()
      ).success(afterGeocode)
      # if there is an error then preferenceAddressMatch will be 'Not Matched', but at least you can proceed.
      .error(afterGeocode)
    )

  Service.validateHouseholdMemberAddress = (callback) ->
    # validate + geocode address
    # errors are handled in the controller
    afterGeocode = (response) ->
      Service.householdMember.geocodingData = response.geocoding_data
      Service.householdMember.preferenceAddressMatch = GeocodingService.preferenceAddressMatch
      Service.addHouseholdMember(Service.householdMember)
      # check if eligibility has changed
      Service.refreshPreferences('all')
      Service.clearAddressRelatedProofForMember(Service.householdMember)
      callback()
    AddressValidationService.validate(
      address: Service.householdMember.home_address
      type: 'home'
    ).success( ->
      GeocodingService.geocode(
        address: Service.householdMember.home_address
        member: Service.householdMember
        applicant: Service.applicant
        listing: Service.listing
        has_nrhp_adhp: Service.listingHasNRHP_or_ADHP()
      ).success(afterGeocode)
      # if there is an error then preferenceAddressMatch will be 'Not Matched' but at least you can proceed.
      .error(afterGeocode)
    )

  Service.applicationWasSubmitted = (application = Service.application) ->
    # from the user's perspective, "Removed" applications should look the same as "Submitted" ones
    _.includes(['Submitted', 'Removed'], application.status)

  Service.applicationCompletionPercentage = (application) ->
    pct = 5
    pct += 30 if application.completedSections.You
    pct += 25 if application.completedSections.Household
    pct += 10 if application.completedSections.Income
    pct += 30 if application.completedSections.Preferences
    pct

  # wrappers for other Service functions
  Service.DOBValid = ShortFormDataService.DOBValid

  Service.hasHouseholdPublicHousingQuestion = ->
    ListingService.hasPreference('assistedHousing')

  Service.formattedBuildingAddress = (listing, display) ->
    ListingService.formattedAddress(listing, 'Building', display)

  Service.listingHasReservedUnitType = (type) ->
    ListingService.listingHasReservedUnitType(Service.listing, type)

  Service.RESERVED_TYPES = ListingService.RESERVED_TYPES

  # TODO: -- REMOVE HARDCODED FEATURES --
  Service.listingIs = ListingService.listingIs

  return Service

############################################################################################
######################################## CONFIG ############################################
############################################################################################

ShortFormApplicationService.$inject = [
  '$translate', '$http', '$state', 'uuid',
  'ListingService', 'ShortFormDataService',
  'AddressValidationService', 'GeocodingService',
  'AnalyticsService', 'FileUploadService'
]

angular
  .module('dahlia.services')
  .service('ShortFormApplicationService', ShortFormApplicationService)
