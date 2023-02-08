CLASS lhc_Travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF travel_status,
        open     TYPE c LENGTH 1 VALUE 'O', " Open
        accepted TYPE c LENGTH 1 VALUE 'A', " Accepted
        canceled TYPE c LENGTH 1 VALUE 'X', " Cancelled
      END OF travel_status.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Travel RESULT result.

    METHODS accepttravel FOR MODIFY
      IMPORTING keys FOR ACTION travel~accepttravel RESULT result.

    METHODS recalctotalprice FOR MODIFY
      IMPORTING keys FOR ACTION travel~recalctotalprice.

    METHODS rejecttravel FOR MODIFY
      IMPORTING keys FOR ACTION travel~rejecttravel RESULT result.
    METHODS calculatetotalprice FOR DETERMINE ON MODIFY
      IMPORTING keys FOR travel~calculatetotalprice.

    METHODS setinitialstatus FOR DETERMINE ON MODIFY
      IMPORTING keys FOR travel~setinitialstatus.

    METHODS calculatetravelid FOR DETERMINE ON SAVE
      IMPORTING keys FOR travel~calculatetravelid.
    METHODS validateagency FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validateagency.

    METHODS validatecustomer FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatecustomer.

    METHODS validatedates FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatedates.

ENDCLASS.

CLASS lhc_Travel IMPLEMENTATION.

  METHOD get_instance_features.

    " Read the travel status of the existing travels
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel FIELDS ( TravelStatus ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels) FAILED failed.

    result = VALUE #( FOR travel IN travels
                        LET is_accepted = COND #( WHEN travel-TravelStatus = travel_status-accepted
                                                    THEN if_abap_behv=>fc-o-disabled
                                                    ELSE if_abap_behv=>fc-o-enabled )
                            is_rejected = COND #( WHEN travel-TravelStatus = travel_status-canceled
                                                    THEN if_abap_behv=>fc-o-disabled
                                                    ELSE if_abap_behv=>fc-o-enabled )
                        IN ( %tky = travel-%tky
                             %action-acceptTravel = is_accepted
                             %action-rejectTravel = is_rejected ) ).

  ENDMETHOD.

  METHOD acceptTravel.

    " Set the new overall status
    MODIFY ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel UPDATE FIELDS ( TravelStatus )
    WITH VALUE #( FOR key IN keys ( %tky = key-%tky
                                    TravelStatus = travel_status-accepted ) )
    FAILED failed REPORTED reported.

    " Fill the response table
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels
                        ( %tky = travel-%tky
                          %param = travel ) ).

  ENDMETHOD.

  METHOD recalcTotalPrice.

    TYPES: BEGIN OF ty_amount_per_currencycode,
             amount        TYPE /dmo/total_price,
             currency_code TYPE /dmo/currency_code,
           END OF ty_amount_per_currencycode.
    DATA: amount_per_currencycode TYPE STANDARD TABLE OF ty_amount_per_currencycode.

    " Read all relevant travel instances.
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel FIELDS ( BookingFee CurrencyCode )
    WITH CORRESPONDING #( keys ) RESULT DATA(travels).

    DELETE travels WHERE CurrencyCode IS INITIAL.

    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).

      " Set the start for the calculation by adding the booking fee.
      amount_per_currencycode = VALUE #( ( amount = <travel>-BookingFee
                                           currency_code = <travel>-CurrencyCode ) ).

      " Read all associated bookings and add them to the total price.
      READ ENTITIES OF ZI_RAP_Travel_np IN LOCAL MODE
      ENTITY Travel BY \_Booking FIELDS ( FlightPrice CurrencyCode )
      WITH VALUE #( ( %tky = <travel>-%tky ) ) RESULT DATA(bookings).

      LOOP AT bookings INTO DATA(booking) WHERE CurrencyCode IS NOT INITIAL.

        COLLECT VALUE ty_amount_per_currencycode( amount = booking-FlightPrice
                                                  currency_code = booking-CurrencyCode )
                                                  INTO amount_per_currencycode.

      ENDLOOP.

      CLEAR <travel>-TotalPrice.
      LOOP AT amount_per_currencycode INTO DATA(single_amount_per_currencycode).

        " If needed do a Currency Conversion
        IF single_amount_per_currencycode-currency_code = <travel>-CurrencyCode.

          <travel>-TotalPrice += single_amount_per_currencycode-amount.

        ELSE.

          /dmo/cl_flight_amdp=>convert_currency(
            EXPORTING
              iv_amount = single_amount_per_currencycode-amount
              iv_currency_code_source = single_amount_per_currencycode-currency_code
              iv_currency_code_target = <travel>-CurrencyCode
              iv_exchange_rate_date = cl_abap_context_info=>get_system_date( )
            IMPORTING
              ev_amount = DATA(total_booking_price_per_curr) ).

          <travel>-TotalPrice += total_booking_price_per_curr.

        ENDIF.

      ENDLOOP.

    ENDLOOP.

    " write back the modified total_price of travels
    MODIFY ENTITIES OF ZI_RAP_Travel_np IN LOCAL MODE
    ENTITY travel UPDATE FIELDS ( TotalPrice )
    WITH CORRESPONDING #( travels ).

  ENDMETHOD.

  METHOD rejectTravel.

    " Set the new overall status
    MODIFY ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel UPDATE
    FIELDS ( TravelStatus ) WITH VALUE #( FOR key IN keys
                                            ( %tky = key-%tky
                                              TravelStatus = travel_status-canceled ) )
    FAILED failed REPORTED reported.

    " Fill the response table
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels
                        ( %tky = travel-%tky
                          %param = travel ) ).

  ENDMETHOD.

  METHOD calculateTotalPrice.

    MODIFY ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY travel EXECUTE recalcTotalPrice
    FROM CORRESPONDING #( keys ) REPORTED DATA(execute_reported).

    reported = CORRESPONDING #( DEEP execute_reported ).

  ENDMETHOD.

  METHOD setInitialStatus.

    " Read relevant travel instance data
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel FIELDS ( TravelStatus ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    " Remove all travel instance data with defined status
    DELETE travels WHERE TravelStatus IS NOT INITIAL.
    CHECK travels IS NOT INITIAL.

    " Set default travel status
    MODIFY ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel UPDATE FIELDS ( TravelStatus )
    WITH VALUE #( FOR travel IN travels
                    ( %tky = travel-%tky
                      TravelStatus = travel_status-open ) )
    REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).

  ENDMETHOD.

  METHOD calculateTravelID.

    " Please note that this is just an example for calculating a field during onSave.
    " This approach does NOT ensure for gap free or unique travel IDs! It just helps to provide a readable ID.
    " The key of this business object is a UUID, calculated by the framework.
    " check if TravelID is already filled
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel FIELDS ( TravelID ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    " remove lines where TravelID is already filled.
    DELETE travels WHERE TravelID IS NOT INITIAL.

    " anything left ?
    CHECK travels IS NOT INITIAL.

    " Select max travel ID
    SELECT SINGLE
    FROM zrap_atrav_np
    FIELDS MAX( travel_id ) AS travelID
    INTO @DATA(max_travelid).

    " Set the travel ID
    MODIFY ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel UPDATE
    FROM VALUE #( FOR travel IN travels INDEX INTO i
                    ( %tky = travel-%tky
                      TravelID = max_travelid + i
                      %control-TravelID = if_abap_behv=>mk-on ) )
    REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).

  ENDMETHOD.

  METHOD validateAgency.
    " Read relevant travel instance data
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel FIELDS ( AgencyID ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    DATA agencies TYPE SORTED TABLE OF /dmo/agency WITH UNIQUE KEY agency_id.

    " Optimization of DB select: extract distinct non-initial agency IDs
    agencies = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING agency_id = AgencyID EXCEPT * ).
    DELETE agencies WHERE agency_id IS INITIAL.

    IF agencies IS NOT INITIAL.

      " Check if agency ID exist
      SELECT FROM /dmo/agency FIELDS agency_id
        FOR ALL ENTRIES IN @agencies
        WHERE agency_id = @agencies-agency_id
        INTO TABLE @DATA(agencies_db).

    ENDIF.

    " Raise msg for non existing and initial agencyID
    LOOP AT travels INTO DATA(travel).

      " Clear state messages that might exist
      APPEND VALUE #( %tky = travel-%tky
                      %state_area  = 'VALIDATE_AGENCY' )
                      TO reported-travel.

      IF travel-AgencyID IS INITIAL OR NOT line_exists( agencies_db[ agency_id = travel-AgencyID ] ).

        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #( %tky = travel-%tky
                        %state_area = 'VALIDATE_AGENCY'
                        %msg = NEW zcm_rap_np(
                                          severity = if_abap_behv_message=>severity-error
                                          textid   = zcm_rap_np=>agency_unknown
                                          agencyid = travel-AgencyID )
                        %element-AgencyID = if_abap_behv=>mk-on )
                        TO reported-travel.

      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validateCustomer.

    " Read relevant travel instance data
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel FIELDS ( CustomerID ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    " Optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING customer_id = CustomerID EXCEPT * ).
    DELETE customers WHERE customer_id IS INITIAL.
    IF customers IS NOT INITIAL.

      " Check if customer ID exist
      SELECT FROM /dmo/customer FIELDS customer_id
        FOR ALL ENTRIES IN @customers
        WHERE customer_id = @customers-customer_id
        INTO TABLE @DATA(customers_db).

    ENDIF.

    " Raise msg for non existing and initial customerID
    LOOP AT travels INTO DATA(travel).

      " Clear state messages that might exist
      APPEND VALUE #( %tky = travel-%tky
                      %state_area = 'VALIDATE_CUSTOMER' )
                     TO reported-travel.

      IF travel-CustomerID IS INITIAL OR NOT line_exists( customers_db[ customer_id = travel-CustomerID ] ).

        APPEND VALUE #(  %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #(  %tky        = travel-%tky
                         %state_area = 'VALIDATE_CUSTOMER'
                         %msg        = NEW zcm_rap_np(
                                           severity   = if_abap_behv_message=>severity-error
                                           textid     = zcm_rap_np=>customer_unknown
                                           customerid = travel-CustomerID )
                         %element-CustomerID = if_abap_behv=>mk-on )
                         TO reported-travel.

      ENDIF.

    ENDLOOP.


  ENDMETHOD.

  METHOD validateDates.

    " Read relevant travel instance data
    READ ENTITIES OF zi_rap_travel_np IN LOCAL MODE
    ENTITY Travel FIELDS ( TravelID BeginDate EndDate ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).

      " Clear state messages that might exist
      APPEND VALUE #( %tky = travel-%tky
                      %state_area = 'VALIDATE_DATES' )
                      TO reported-travel.

      IF travel-EndDate < travel-BeginDate.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky = travel-%tky
                        %state_area = 'VALIDATE_DATES'
                        %msg = NEW zcm_rap_np( severity  = if_abap_behv_message=>severity-error
                                               textid    = zcm_rap_np=>date_interval
                                               begindate = travel-BeginDate
                                               enddate   = travel-EndDate
                                               travelid  = travel-TravelID )
                        %element-BeginDate = if_abap_behv=>mk-on
                        %element-EndDate = if_abap_behv=>mk-on ) TO reported-travel.

      ELSEIF travel-BeginDate < cl_abap_context_info=>get_system_date( ).

        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky = travel-%tky
                        %state_area = 'VALIDATE_DATES'
                        %msg = NEW zcm_rap_np( severity  = if_abap_behv_message=>severity-error
                                               textid    = zcm_rap_np=>begin_date_before_system_date
                                               begindate = travel-BeginDate )
                        %element-BeginDate = if_abap_behv=>mk-on )
                        TO reported-travel.

      ENDIF.

    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
