local SNIPE_RESULTS_TABLE_LAYOUT = {
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "minPrice" },
    headerText = AUCTIONATOR_L_RESULTS_PRICE_COLUMN,
    cellTemplate = "AuctionatorPriceCellTemplate",
    cellParameters = { "minPrice" },
    width = 140
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "comparisonPrice" },
    headerText = POINT_BLANK_SNIPER_L_COMPARISON_PRICE,
    cellTemplate = "AuctionatorPriceCellTemplate",
    cellParameters = { "comparisonPrice" },
    defaultHide = true,
    width = 140
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "name" },
    headerText = AUCTIONATOR_L_RESULTS_NAME_COLUMN,
    cellTemplate = "AuctionatorItemKeyCellTemplate"
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "profit" },
    headerText = POINT_BLANK_SNIPER_L_PROFIT,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "profitText" },
    width = 140
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "discount" },
    headerText = POINT_BLANK_SNIPER_L_DISCOUNT,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "discountText" },
    width = 80
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "saleRate" },
    headerText = POINT_BLANK_SNIPER_L_SALE_RATE,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "saleRateText" },
    width = 80
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "totalQuantity" },
    headerText = POINT_BLANK_SNIPER_L_TOTAL_QUANTITY,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "totalQuantityText" },
    width = 80
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "isNew" },
    headerText = POINT_BLANK_SNIPER_L_IS_NEW,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "isNew" },
    width = 80,
    defaultHide = true,
  },
}

PointBlankSniperDataProviderMixin = CreateFromMixins(AuctionatorDataProviderMixin, AuctionatorItemKeyLoadingMixin)

function PointBlankSniperDataProviderMixin:OnLoad()
  Auctionator.Debug.Message("PointBlankSniperDataProviderMixin:OnLoad()")

  self:SetUpEvents()

  AuctionatorDataProviderMixin.OnLoad(self)
  AuctionatorItemKeyLoadingMixin.OnLoad(self)

  self:Reset()
end

function PointBlankSniperDataProviderMixin:SetUpEvents()
  Auctionator.EventBus:RegisterSource(self, "PointBlankSniper Data Provider")

  Auctionator.EventBus:Register(self, {
    PointBlankSniper.Events.SnipeSearchStart,
    PointBlankSniper.Events.SnipeSearchNewResults,
    PointBlankSniper.Events.SnipeSearchComplete,
    PointBlankSniper.Events.SnipeSearchAbort,
  })

  self.lastRound = {}
  self.thisRound = {}
end

local function ResultKey(result)
  return Auctionator.Utilities.ItemKeyString(result.itemKey) .. " " .. result.minPrice
end

-- Fraction of the sale price kept after the auction house cut
local AH_CUT_MULTIPLIER = 0.95

local function AddMarketInfo(r, priceSource)
  local reference = priceSource:GetReferencePrice(r.itemKey)
  if reference and reference > 0 and r.minPrice > 0 then
    r.profit = math.floor(reference * AH_CUT_MULTIPLIER - r.minPrice)
    if r.profit < 0 then
      r.profitText = "-" .. GetMoneyString(-r.profit, true)
    else
      r.profitText = GetMoneyString(r.profit, true)
    end
    r.discount = reference / r.minPrice
    r.discountText = string.format("%.1fx", r.discount)
  else
    r.profit = nil
    r.profitText = ""
    r.discount = nil
    r.discountText = ""
  end

  r.saleRate = PointBlankSniper.PriceCheck.GetSaleRate(r.itemKey)
  r.saleRateText = r.saleRate and string.format("%.3f", r.saleRate) or ""

  r.totalQuantityText = tostring(r.totalQuantity)
end

function PointBlankSniperDataProviderMixin:ProcessThisScan(results, lastBatch)
  local showHighlights = PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.HIGHLIGHT_NEW_RESULTS)
  local priceSource = PointBlankSniper.PriceCheck.Get()
  local newResults = CopyTable(results)
  for _, r in ipairs(newResults) do
    local key = ResultKey(r)
    self.thisRound[key] = true
    local isNew = not self.lastRound[key]
    r.highlight = isNew and showHighlights
    r.isNew = isNew and AUCTIONATOR_L_UNDERCUT_YES or AUCTIONATOR_L_UNDERCUT_NO
    AddMarketInfo(r, priceSource)
  end
  self:AppendEntries(newResults, lastBatch)
end

function PointBlankSniperDataProviderMixin:ReceiveEvent(eventName, results, ...)
  if eventName == PointBlankSniper.Events.SnipeSearchStart then
    self.onSearchStarted()
    self.thisRound = {}
  elseif eventName == PointBlankSniper.Events.SnipeSearchNewResults then
    self.onPreserveScroll()
    self.onSearchStarted()
    self:ProcessThisScan(results, false)
  elseif eventName == PointBlankSniper.Events.SnipeSearchComplete then
    self.onPreserveScroll()
    self:Reset()
    self:ProcessThisScan(results, true)
    self.lastRound = self.thisRound
  elseif eventName == PointBlankSniper.Events.SnipeSearchAbort then
    self.onPreserveScroll()
    self:AppendEntries({}, true)
    self.lastRound = self.thisRound
  end
end

function PointBlankSniperDataProviderMixin:UniqueKey(entry)
  return Auctionator.Utilities.ItemKeyString(entry.itemKey)
end

-- Like NumberComparator, but entries missing the field always sort last
local function OptionalNumberComparator(sortDirection, fieldName)
  local comparator = Auctionator.Utilities.NumberComparator(sortDirection, fieldName)
  return function(left, right)
    if left[fieldName] == nil or right[fieldName] == nil then
      return left[fieldName] ~= nil and right[fieldName] == nil
    end
    return comparator(left, right)
  end
end

local COMPARATORS = {
  minPrice = Auctionator.Utilities.NumberComparator,
  comparisonPrice = OptionalNumberComparator,
  name = Auctionator.Utilities.StringComparator,
  profit = OptionalNumberComparator,
  discount = OptionalNumberComparator,
  saleRate = OptionalNumberComparator,
  totalQuantity = Auctionator.Utilities.NumberComparator,
  isNew = Auctionator.Utilities.StringComparator,
}

function PointBlankSniperDataProviderMixin:Sort(fieldName, sortDirection)
  local comparator = COMPARATORS[fieldName](sortDirection, fieldName)

  table.sort(self.results, function(left, right)
    return comparator(left, right)
  end)

  self:SetDirty()
end

function PointBlankSniperDataProviderMixin:GetTableLayout()
  return SNIPE_RESULTS_TABLE_LAYOUT
end

function PointBlankSniperDataProviderMixin:GetColumnHideStates()
  return PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.COLUMNS)
end

function PointBlankSniperDataProviderMixin:GetRowTemplate()
  return "PointBlankSniperResultsRowTemplate"
end
