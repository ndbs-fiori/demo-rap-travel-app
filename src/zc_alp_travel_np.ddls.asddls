@AbapCatalog.sqlViewName: 'ZCALPTRAVELNP'
@AbapCatalog.compiler.compareFilter: true
@AbapCatalog.preserveKey: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'test alp'
@Metadata.allowExtensions: true
define view ZC_ALP_TRAVEL_NP as select from ZI_RAP_Travel_NP {
    key TravelUUID,
    TravelID,
    AgencyID,
    CustomerID,
    BeginDate,
    EndDate,
    BookingFee,
    @DefaultAggregation: #SUM
    TotalPrice,
    CurrencyCode,
    Description,
    TravelStatus,
    CreatedBy,
    CreatedAt,
    LastChangedBy,
    LastChangedAt,
    LocalLastChangedAt,
    /* Associations */
    _Agency,
    _Booking,
    _Currency,
    _Customer
}
