-- ImprovedTalents
-- Uses SavedVariables (global): TALENTSVIEWER_SV
-- Ported for WoW 3.3.5 (WotLK)

local function Debug(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage('ImprovedTalents: ' .. msg)
    else
        print('ImprovedTalents: ' .. msg)
    end
end
Debug('file loaded')

local SV
local frame
local treeFrames = {}
local playerTalentButtons = {}
local petTalentButtons = {}
local branchArrays = {}
local branchTextures = {}
local arrowTextures = {}
local isPetMode = false
local petButtonsCreated = false
local lastLayoutNumTabs = -1
local currentTalentGroup = 1
local previewMode = false

local PLAYER_TALENTS_PER_TIER = 5
local PET_TALENTS_PER_TIER = 3

-- Forward declarations needed for cross-references
local Update
local CreatePetTalents
local UpdatePetButton
local UpdateSpecButtons
local UpdatePreviewBar

local TALENT_BRANCH_TEXTURECOORDS = {
    up = {[1] = {0.12890625, 0.25390625, 0, 0.484375}, [-1] = {0.12890625, 0.25390625, 0.515625, 1.0}},
    down = {[1] = {0, 0.125, 0, 0.484375}, [-1] = {0, 0.125, 0.515625, 1.0}},
    left = {[1] = {0.2578125, 0.3828125, 0, 0.5}, [-1] = {0.2578125, 0.3828125, 0.5, 1.0}},
    right = {[1] = {0.2578125, 0.3828125, 0, 0.5}, [-1] = {0.2578125, 0.3828125, 0.5, 1.0}},
    topright = {[1] = {0.515625, 0.640625, 0, 0.5}, [-1] = {0.515625, 0.640625, 0.5, 1.0}},
    topleft = {[1] = {0.640625, 0.515625, 0, 0.5}, [-1] = {0.640625, 0.515625, 0.5, 1.0}},
    bottomright = {[1] = {0.38671875, 0.51171875, 0, 0.5}, [-1] = {0.38671875, 0.51171875, 0.5, 1.0}},
    bottomleft = {[1] = {0.51171875, 0.38671875, 0, 0.5}, [-1] = {0.51171875, 0.38671875, 0.5, 1.0}},
    tdown = {[1] = {0.64453125, 0.76953125, 0, 0.5}, [-1] = {0.64453125, 0.76953125, 0.5, 1.0}},
    tup = {[1] = {0.7734375, 0.8984375, 0, 0.5}, [-1] = {0.7734375, 0.8984375, 0.5, 1.0}}
}

local TALENT_ARROW_TEXTURECOORDS = {
    top = {[1] = {0, 0.5, 0, 0.5}, [-1] = {0, 0.5, 0.5, 1.0}},
    right = {[1] = {1.0, 0.5, 0, 0.5}, [-1] = {1.0, 0.5, 0.5, 1.0}},
    left = {[1] = {0.5, 1.0, 0, 0.5}, [-1] = {0.5, 1.0, 0.5, 1.0}}
}

StaticPopupDialogs['IMPROVEDTALENTS_CONFIRM_LEARN_PREVIEW'] = {
    text = 'Learn these talents?',
    button1 = YES,
    button2 = NO,
    OnAccept = function() pcall(LearnPreviewTalents, isPetMode) end,
    hideOnEscape = 1,
    timeout = 0,
    exclusive = 1,
}

local function HasPetTalents()
    return UnitExists('pet') and GetNumTalentTabs(false, true) > 0
end

local function CreateScaleCheckbox(parent)
    local cb = CreateFrame('CheckButton', nil, parent, 'UICheckButtonTemplate')
    cb:SetWidth(20)
    cb:SetHeight(20)
    cb.text = cb:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    cb.text:SetPoint('LEFT', cb, 'RIGHT', 4, 0)
    cb.text:SetText('Small')
    return cb
end

local function CreateSpecButton(parent, group)
    local btn = CreateFrame('Button', nil, parent)
    btn:SetWidth(36); btn:SetHeight(36)

    local bg = btn:CreateTexture(nil, 'BACKGROUND')
    bg:SetTexture('Interface\\SpellBook\\SpellBook-SkillLineTab')
    bg:SetWidth(64); bg:SetHeight(64)
    bg:SetPoint('TOPLEFT', btn, 'TOPLEFT', -3, 11)

    local icon = btn:CreateTexture(nil, 'ARTWORK')
    icon:SetWidth(28); icon:SetHeight(28)
    icon:SetPoint('CENTER', btn, 'CENTER', 0, 0)
    btn.icon = icon

    -- Gold glow shown when this spec is the currently active (live) one
    local glow = btn:CreateTexture(nil, 'OVERLAY')
    glow:SetTexture('Interface\\SpellBook\\SpellBook-SkillLineTab-Glow')
    glow:SetBlendMode('ADD')
    glow:SetWidth(64); glow:SetHeight(64)
    glow:SetPoint('TOPLEFT', btn, 'TOPLEFT', -3, 11)
    glow:Hide()
    btn.glow = glow

    -- Gold overlay shown when this spec is the currently viewed one
    local selected = btn:CreateTexture(nil, 'OVERLAY')
    selected:SetTexture('Interface\\Buttons\\CheckButtonHilight')
    selected:SetBlendMode('ADD')
    selected:SetAllPoints(btn)
    selected:Hide()
    btn.selected = selected

    local highlight = btn:CreateTexture(nil, 'HIGHLIGHT')
    highlight:SetTexture('Interface\\Buttons\\ButtonHilight-Square')
    highlight:SetBlendMode('ADD')
    highlight:SetAllPoints(btn)

    btn.group = group
    btn:Hide()
    btn:SetScript('OnClick', function()
        currentTalentGroup = group
        Update()
    end)
    btn:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        local activeGroup = GetActiveTalentGroup()
        local label = group == 1 and 'Primary Spec' or 'Secondary Spec'
        if group == activeGroup then label = label .. ' |cFF00FF00(Active)|r' end
        GameTooltip:SetText(label)
        GameTooltip:Show()
    end)
    btn:SetScript('OnLeave', function() GameTooltip:Hide() end)
    return btn
end

local function CreateMainFrame()
    frame = CreateFrame('Frame', 'BLF_TalentFrame', UIParent)
    frame:SetWidth(1020)
    frame:SetHeight(700)
    frame:SetFrameStrata('HIGH')
    frame:EnableMouse(true)
    frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
    frame:SetBackdrop({ bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background' })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetScript('OnMouseDown', function(self) self:StartMoving() end)
    frame:SetScript('OnMouseUp', function(self) self:StopMovingOrSizing() end)

    local closeButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    closeButton:SetWidth(48)
    closeButton:SetHeight(22)
    closeButton:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -10, -6)
    closeButton:SetText('Close')
    closeButton:SetScript('OnClick', function()
        pcall(PlaySound, 'TalentScreenClose')
        frame:Hide()
        if UpdateMicroButtons then UpdateMicroButtons() end
    end)

    local headerText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    headerText:SetText('Talents')
    headerText:SetPoint('TOP', frame, 'TOP', 0, -6)
    frame.headerText = headerText

    local pointsLeft = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    pointsLeft:SetPoint('BOTTOM', frame, 'BOTTOM', 0, 20)
    frame.pointsLeft = pointsLeft

    local scaleCheckbox = CreateScaleCheckbox(frame)
    scaleCheckbox:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 12, 18)
    frame.scaleCheckbox = scaleCheckbox

    local previewCheckbox = CreateFrame('CheckButton', nil, frame, 'UICheckButtonTemplate')
    previewCheckbox:SetWidth(20)
    previewCheckbox:SetHeight(20)
    previewCheckbox:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 12, 40)
    previewCheckbox.text = previewCheckbox:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    previewCheckbox.text:SetPoint('LEFT', previewCheckbox, 'RIGHT', 4, 0)
    previewCheckbox.text:SetText('Preview')
    previewCheckbox:SetScript('OnClick', function(self)
        previewMode = self:GetChecked() and true or false
        Update()
    end)
    frame.previewCheckbox = previewCheckbox

    local learnButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    learnButton:SetWidth(80)
    learnButton:SetHeight(22)
    learnButton:SetPoint('BOTTOM', frame, 'BOTTOM', 44, 45)
    learnButton:SetText('Learn')
    learnButton:Hide()
    learnButton:SetScript('OnClick', function()
        StaticPopup_Show('IMPROVEDTALENTS_CONFIRM_LEARN_PREVIEW')
    end)
    frame.learnButton = learnButton

    local resetButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    resetButton:SetWidth(80)
    resetButton:SetHeight(22)
    resetButton:SetPoint('RIGHT', learnButton, 'LEFT', -4, 0)
    resetButton:SetText('Reset')
    resetButton:Hide()
    resetButton:SetScript('OnClick', function()
        pcall(ResetGroupPreviewTalentPoints, isPetMode, currentTalentGroup)
    end)
    frame.resetButton = resetButton

    -- Pet talents toggle button (shown only when player has a pet with talents)
    local petButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    petButton:SetWidth(80)
    petButton:SetHeight(22)
    petButton:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -10, 6)
    petButton:SetText('Pet')
    petButton:Hide()
    petButton:SetScript('OnClick', function()
        if isPetMode then
            -- Switch back to player mode
            isPetMode = false
            for _, btn in pairs(petTalentButtons) do btn:Hide() end
        else
            -- Switch to pet mode
            isPetMode = true
            if not petButtonsCreated then
                CreatePetTalents()
            end
            for _, btn in pairs(playerTalentButtons) do btn:Hide() end
        end
        Update()
    end)
    frame.petButton = petButton

    -- Dual-spec buttons (top-left, hidden when player has only one spec)
    local spec1Button = CreateSpecButton(frame, 1)
    spec1Button:SetPoint('TOPLEFT', frame, 'TOPLEFT', 10, -4)
    frame.spec1Button = spec1Button

    local spec2Button = CreateSpecButton(frame, 2)
    spec2Button:SetPoint('LEFT', spec1Button, 'RIGHT', 4, 0)
    frame.spec2Button = spec2Button

    local activateButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    activateButton:SetWidth(80); activateButton:SetHeight(22)
    activateButton:SetPoint('LEFT', spec2Button, 'RIGHT', 8, 7)
    activateButton:SetText('Set Active')
    activateButton:Hide()
    activateButton:SetScript('OnClick', function()
        SetActiveTalentGroup(currentTalentGroup)
    end)
    frame.activateButton = activateButton

    if SV and SV['TalentFrameSmall'] then frame:SetScale(0.8); scaleCheckbox:SetChecked(true) end
    scaleCheckbox:SetScript('OnClick', function(self)
        if self:GetChecked() then
            frame:SetScale(0.8)
            if SV then SV['TalentFrameSmall'] = 1; TALENTSVIEWER_SV = SV end
        else
            frame:SetScale(1.0)
            if SV then SV['TalentFrameSmall'] = nil; TALENTSVIEWER_SV = SV end
        end
    end)

    frame:Hide()
    table.insert(UISpecialFrames, 'BLF_TalentFrame')
end

UpdatePetButton = function()
    if not frame then return end
    if HasPetTalents() then
        frame.petButton:Show()
        frame.petButton:SetText(isPetMode and 'Player' or 'Pet')
    else
        frame.petButton:Hide()
        if isPetMode then
            isPetMode = false
            for _, btn in pairs(petTalentButtons) do btn:Hide() end
        end
    end
end

UpdateSpecButtons = function()
    if not frame then return end
    local n = GetNumTalentGroups()
    if n < 2 then
        frame.spec1Button:Hide()
        frame.spec2Button:Hide()
        frame.activateButton:Hide()
        return
    end

    frame.spec1Button:Show()
    frame.spec2Button:Show()

    local activeGroup = GetActiveTalentGroup()

    for _, btn in ipairs({frame.spec1Button, frame.spec2Button}) do
        local g = btn.group
        -- Icon: use the icon of the tab with the most points spent in this spec
        local bestIcon, bestPts = nil, -1
        for tab = 1, 3 do
            local _, icon, pts = GetTalentTabInfo(tab, false, false, g)
            if pts and pts > bestPts then
                bestPts = pts
                bestIcon = icon
            end
        end
        if bestPts > 0 and bestIcon then
            btn.icon:SetTexture(bestIcon)
        else
            SetPortraitTexture(btn.icon, 'player')
        end
        -- Gold overlay: viewing this spec
        if g == currentTalentGroup then btn.selected:Show() else btn.selected:Hide() end
        -- Glow: this is the live active spec
        if g == activeGroup then btn.glow:Show() else btn.glow:Hide() end
    end

    -- "Set Active" only when viewing the inactive spec (and not in pet mode)
    if not isPetMode and currentTalentGroup ~= activeGroup then
        frame.activateButton:Show()
    else
        frame.activateButton:Hide()
    end
end

UpdatePreviewBar = function()
    if not frame then return end
    local isActiveSpec = isPetMode or (currentTalentGroup == GetActiveTalentGroup())
    local cp = GetUnspentTalentPoints(false, isPetMode, currentTalentGroup)
    if previewMode and isActiveSpec and cp > 0 then
        frame.learnButton:Show()
        frame.resetButton:Show()
        local ok, staged = pcall(GetGroupPreviewTalentPointsSpent, isPetMode, currentTalentGroup)
        if ok and staged > 0 then
            frame.learnButton:Enable()
            frame.resetButton:Enable()
        else
            frame.learnButton:Disable()
            frame.resetButton:Disable()
        end
    else
        frame.learnButton:Hide()
        frame.resetButton:Hide()
    end
end

-- Resize frame width and center tree panels for the given tab count.
-- Only does work when the tab count actually changes.
local function LayoutTreeFrames(numTabs)
    if numTabs == lastLayoutNumTabs then return end
    lastLayoutNumTabs = numTabs

    -- totalTreesWidth: each tree is 300px wide, 40px gap between trees
    local totalTreesWidth = numTabs * 300 + math.max(0, numTabs - 1) * 40
    -- 40px total horizontal padding; enforce a minimum so bottom controls fit
    local frameWidth = math.max(totalTreesWidth + 40, 440)
    frame:SetWidth(frameWidth)

    -- startX: left edge of the first tree frame, centered in the new frame width
    local startX = (frameWidth - totalTreesWidth) / 2
    for i = 1, 3 do
        local tf = treeFrames[i].frame
        tf:ClearAllPoints()
        if i <= numTabs then
            tf:SetPoint('TOPLEFT', frame, 'TOPLEFT', startX + (i - 1) * 340, -55)
            tf:Show()
        else
            tf:Hide()
        end
    end
end

local function CreateTreeFrames()
    local xOffsets = {0, 340, 680}
    for i = 1, 3 do
        local treeFrame = CreateFrame('Frame', nil, frame)
        treeFrame:SetWidth(300)
        treeFrame:SetHeight(750)
        treeFrame:SetPoint('TOPLEFT', frame, 'TOPLEFT', xOffsets[i] + 20, -50)
        local header = treeFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
        header:SetPoint('TOP', treeFrame, 'TOP', 0, 20)

        local pointsText = treeFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        pointsText:SetPoint('TOP', treeFrame, 'TOP', 0, 0)
        pointsText:SetTextColor(1, 1, 1)

        local branchFrame = CreateFrame('Frame', nil, treeFrame)
        branchFrame:SetAllPoints()

        local arrowFrame = CreateFrame('Frame', nil, treeFrame)
        arrowFrame:SetAllPoints()

        local bgTopLeft = treeFrame:CreateTexture(nil, 'BACKGROUND')
        bgTopLeft:SetWidth(200)
        bgTopLeft:SetPoint('TOPLEFT', treeFrame, 'TOPLEFT', 20, -30)
        local bgTopRight = treeFrame:CreateTexture(nil, 'BACKGROUND')
        bgTopRight:SetWidth(100)
        bgTopRight:SetPoint('TOPRIGHT', treeFrame, 'TOPRIGHT', 20, -30)
        local bgBottomLeft = treeFrame:CreateTexture(nil, 'BACKGROUND')
        bgBottomLeft:SetWidth(200)
        bgBottomLeft:SetPoint('TOPLEFT', bgTopLeft, 'BOTTOMLEFT', 0, 0)
        local bgBottomRight = treeFrame:CreateTexture(nil, 'BACKGROUND')
        bgBottomRight:SetWidth(100)
        bgBottomRight:SetPoint('TOPRIGHT', bgTopRight, 'BOTTOMRIGHT', 0, 0)

        local _, _, _, fileName = GetTalentTabInfo(i)
        local base = fileName and ('Interface\\TalentFrame\\' .. fileName .. '-') or 'Interface\\TalentFrame\\MageFire-'
        bgTopLeft:SetTexture(base .. 'TopLeft');        bgTopLeft:SetAlpha(0.7)
        bgTopRight:SetTexture(base .. 'TopRight');      bgTopRight:SetAlpha(0.7)
        bgBottomLeft:SetTexture(base .. 'BottomLeft');  bgBottomLeft:SetAlpha(0.7)
        bgBottomRight:SetTexture(base .. 'BottomRight'); bgBottomRight:SetAlpha(0.7)

        local borderTop = treeFrame:CreateTexture(nil, 'OVERLAY')
        borderTop:SetTexture('Interface\\Buttons\\WHITE8X8')
        borderTop:SetVertexColor(0,0,0, .4)
        borderTop:SetWidth(265); borderTop:SetHeight(4)
        borderTop:SetPoint('TOPLEFT', bgTopLeft, 'TOPLEFT', 2, 0)

        local borderLeft = treeFrame:CreateTexture(nil, 'OVERLAY')
        borderLeft:SetTexture('Interface\\Buttons\\WHITE8X8')
        borderLeft:SetVertexColor(0,0,0, .4)
        borderLeft:SetWidth(4)
        borderLeft:SetPoint('TOPLEFT',    treeFrame, 'TOPLEFT',    20, -30)
        borderLeft:SetPoint('BOTTOMLEFT', treeFrame, 'BOTTOMLEFT', 20,   0)

        local borderRight = treeFrame:CreateTexture(nil, 'OVERLAY')
        borderRight:SetTexture('Interface\\Buttons\\WHITE8X8')
        borderRight:SetVertexColor(0,0,0, .4)
        borderRight:SetWidth(4)
        borderRight:SetPoint('TOPRIGHT',    treeFrame, 'TOPRIGHT',    -10, -30)
        borderRight:SetPoint('BOTTOMRIGHT', treeFrame, 'BOTTOMRIGHT', -10,   0)

        local borderBottom = treeFrame:CreateTexture(nil, 'OVERLAY')
        borderBottom:SetTexture('Interface\\Buttons\\WHITE8X8')
        borderBottom:SetGradientAlpha('VERTICAL', 0, 0, 0, .9, 0, 0, 0, 0)
        borderBottom:SetWidth(270); borderBottom:SetHeight(40)
        borderBottom:SetPoint('BOTTOMLEFT', treeFrame, 'BOTTOMLEFT', 20, 0)

        local whiteBottom = treeFrame:CreateTexture(nil, 'BACKGROUND')
        whiteBottom:SetTexture('Interface\\Buttons\\WHITE8X8')
        whiteBottom:SetGradientAlpha('VERTICAL', 0, 0, 0, 0, 0, 0, 0, .9)
        whiteBottom:SetWidth(270); whiteBottom:SetHeight(70)
        whiteBottom:SetPoint('TOP', borderBottom, 'BOTTOM', 0, 1)

        branchArrays[i] = {}
        branchTextures[i] = {}
        arrowTextures[i] = {}
        for tier = 1, 11 do
            branchArrays[i][tier] = {}
            for col = 1, 4 do
                branchArrays[i][tier][col] = {id=nil, up=0, left=0, right=0, down=0, leftArrow=0, rightArrow=0, topArrow=0}
            end
        end

        treeFrames[i] = {
            frame = treeFrame, header = header, pointsText = pointsText,
            branchFrame = branchFrame, arrowFrame = arrowFrame,
            bgTopLeft = bgTopLeft, bgTopRight = bgTopRight,
            bgBottomLeft = bgBottomLeft, bgBottomRight = bgBottomRight
        }
    end
end

local function CreateTalentButton(tabIndex, talentIndex, tier, column, isPet)
    local treeFrame = treeFrames[tabIndex].frame
    local button = CreateFrame('Button', nil, treeFrame)
    button:SetWidth(32); button:SetHeight(32)
    button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    local x = (column - 1) * 63 + 35
    local y = -(tier - 1) * 63 - 50
    button:SetPoint('TOPLEFT', treeFrame, 'TOPLEFT', x + 10, y)

    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetAllPoints()

    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
    border:SetBlendMode('ADD')
    border:SetWidth(64); border:SetHeight(64)
    border:SetPoint('CENTER', button, 'CENTER', 0, 0)

    local hoverBorder = button:CreateTexture(nil, 'OVERLAY')
    hoverBorder:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
    hoverBorder:SetBlendMode('ADD')
    hoverBorder:SetWidth(64); hoverBorder:SetHeight(64)
    hoverBorder:SetPoint('CENTER', button, 'CENTER', 0, 0)
    hoverBorder:SetVertexColor(1, 0.82, 0)
    hoverBorder:Hide()

    local rankBg = button:CreateTexture(nil, 'OVERLAY')
    rankBg:SetTexture(0, 0, 0, .5)
    rankBg:SetWidth(37); rankBg:SetHeight(12)
    rankBg:SetPoint('TOP', button, 'BOTTOM', 0, -2)

    local rank = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    rank:SetPoint('BOTTOM', button, 'BOTTOM', 0, -12)

    button.icon = icon; button.border = border; button.hoverBorder = hoverBorder; button.rank = rank
    button.tabIndex = tabIndex; button.talentIndex = talentIndex; button.isPet = isPet or false

    button:SetScript('OnClick', function(self, mouseButton)
        if mouseButton == 'RightButton' then
            if previewMode then
                if self.isPet then
                    pcall(AddPreviewTalentPoints, self.tabIndex, self.talentIndex, -1, true, 1)
                else
                    pcall(AddPreviewTalentPoints, self.tabIndex, self.talentIndex, -1, false, currentTalentGroup)
                end
            end
            return
        end

        -- Left button
        local _, _, talentTier, _, talentRank, talentMaxRank, _, talentMeetsPrereq
        local characterPoints, tabPointsSpent
        if self.isPet then
            _, _, talentTier, _, talentRank, talentMaxRank, _, talentMeetsPrereq =
                GetTalentInfo(self.tabIndex, self.talentIndex, false, true, 1)
            characterPoints = GetUnspentTalentPoints(false, true, 1)
            local _,_,pts = GetTalentTabInfo(self.tabIndex, false, true, 1)
            tabPointsSpent = pts
        else
            -- Active-spec guard applies in both direct and preview mode
            if currentTalentGroup ~= GetActiveTalentGroup() then return end
            _, _, talentTier, _, talentRank, talentMaxRank, _, talentMeetsPrereq =
                GetTalentInfo(self.tabIndex, self.talentIndex, false, false, currentTalentGroup)
            characterPoints = GetUnspentTalentPoints(false, false, currentTalentGroup)
            local _,_,pts = GetTalentTabInfo(self.tabIndex, false, false, currentTalentGroup)
            tabPointsSpent = pts
        end
        local tierPoints = self.isPet and PET_TALENTS_PER_TIER or PLAYER_TALENTS_PER_TIER
        local talentTierUnlocked = ((talentTier - 1) * tierPoints <= tabPointsSpent)

        if talentMeetsPrereq and talentTierUnlocked and characterPoints > 0 and talentRank < talentMaxRank then
            if previewMode then
                if self.isPet then
                    pcall(AddPreviewTalentPoints, self.tabIndex, self.talentIndex, 1, true, 1)
                else
                    pcall(AddPreviewTalentPoints, self.tabIndex, self.talentIndex, 1, false, currentTalentGroup)
                end
            else
                if self.isPet then
                    LearnTalent(self.tabIndex, self.talentIndex, true)
                else
                    LearnTalent(self.tabIndex, self.talentIndex, false, currentTalentGroup)
                end
            end
        end
    end)

    button:SetScript('OnEnter', function(self)
        self.hoverBorder:Show()
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        if self.isPet then
            GameTooltip:SetTalent(self.tabIndex, self.talentIndex, false, true, 1, previewMode)
        else
            GameTooltip:SetTalent(self.tabIndex, self.talentIndex, false, false, currentTalentGroup, previewMode)
        end
    end)
    button:SetScript('OnLeave', function(self)
        self.hoverBorder:Hide()
        GameTooltip:Hide()
    end)

    return button
end

local function CheckPrereqsMaxed(tabIndex, talentIndex, isPet)
    local prereqs
    if isPet then
        prereqs = {GetTalentPrereqs(tabIndex, talentIndex, false, true, 1)}
    else
        prereqs = {GetTalentPrereqs(tabIndex, talentIndex, false, false, currentTalentGroup)}
    end
    for i = 1, #prereqs, 3 do
        local prereqTier, prereqColumn, prereqMaxed = prereqs[i], prereqs[i+1], prereqs[i+2]
        if prereqTier and prereqColumn and not prereqMaxed then
            return nil
        end
    end
    return 1
end

local function ResetBranches(tabIndex)
    for tier = 1, 11 do
        for col = 1, 4 do
            local node = branchArrays[tabIndex][tier][col]
            node.id = nil; node.up = 0; node.down = 0; node.left = 0; node.right = 0
            node.rightArrow = 0; node.leftArrow = 0; node.topArrow = 0
        end
    end
    for i = 1, #branchTextures[tabIndex] do branchTextures[tabIndex][i]:Hide() end
    for i = 1, #arrowTextures[tabIndex] do arrowTextures[tabIndex][i]:Hide() end
end

local function GetTexture(tabIndex, isBranch)
    local textures = isBranch and branchTextures[tabIndex] or arrowTextures[tabIndex]
    for i = 1, #textures do
        if not textures[i]:IsVisible() then textures[i]:Show(); return textures[i] end
    end
    local parent = isBranch and treeFrames[tabIndex].branchFrame or treeFrames[tabIndex].arrowFrame
    local layer = isBranch and 'ARTWORK' or 'OVERLAY'
    local texturePath = isBranch and 'Interface\\TalentFrame\\UI-TalentBranches' or 'Interface\\TalentFrame\\UI-TalentArrows'
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(texturePath)
    texture:SetWidth(32); texture:SetHeight(32)
    table.insert(textures, texture)
    texture:Show()
    return texture
end

local function SetBranchTexture(tabIndex, texCoords, xOffset, yOffset)
    local texture = GetTexture(tabIndex, true)
    texture:SetTexCoord(texCoords[1], texCoords[2], texCoords[3], texCoords[4])
    texture:SetPoint('TOPLEFT', treeFrames[tabIndex].branchFrame, 'TOPLEFT', xOffset+8, yOffset)
end

local function SetArrowTexture(tabIndex, texCoords, xOffset, yOffset)
    local texture = GetTexture(tabIndex, false)
    texture:SetTexCoord(texCoords[1], texCoords[2], texCoords[3], texCoords[4])
    texture:SetPoint('TOPLEFT', treeFrames[tabIndex].arrowFrame, 'TOPLEFT', xOffset+8, yOffset)
end

local function DrawTalentLines(tabIndex, buttonTier, buttonColumn, tier, column, requirementsMet)
    local reqMet = requirementsMet and 1 or -1
    if buttonColumn == column then
        for i = tier, buttonTier - 1 do
            branchArrays[tabIndex][i][buttonColumn].down = reqMet
            if (i + 1) <= (buttonTier - 1) then
                branchArrays[tabIndex][i + 1][buttonColumn].up = reqMet
            end
        end
        branchArrays[tabIndex][buttonTier][buttonColumn].topArrow = reqMet
    elseif buttonTier == tier then
        local left = math.min(buttonColumn, column)
        local right = math.max(buttonColumn, column)
        for i = left, right - 1 do
            branchArrays[tabIndex][tier][i].right = reqMet
            branchArrays[tabIndex][tier][i+1].left = reqMet
        end
        if buttonColumn < column then
            branchArrays[tabIndex][buttonTier][buttonColumn].rightArrow = reqMet
        else
            branchArrays[tabIndex][buttonTier][buttonColumn].leftArrow = reqMet
        end
    end
end

local function SetTalentPrereqs(tabIndex, buttonTier, buttonColumn, forceDesaturated, tierUnlocked, ...)
    local requirementsMet
    if tierUnlocked and not forceDesaturated then requirementsMet = 1 else requirementsMet = nil end
    local numArgs = select('#', ...)
    for i = 1, numArgs, 3 do
        local tier        = select(i,   ...)
        local column      = select(i+1, ...)
        local isLearnable = select(i+2, ...)
        if not isLearnable or forceDesaturated then requirementsMet = nil end
        if tier and column then
            DrawTalentLines(tabIndex, buttonTier, buttonColumn, tier, column, requirementsMet)
        end
    end
    return requirementsMet
end

local function DrawBranches(tabIndex)
    for tier = 1, 11 do
        for col = 1, 4 do
            local node = branchArrays[tabIndex][tier][col]
            local xOffset = (col - 1) * 63 + 35 + 2
            local yOffset = -(tier - 1) * 63 - 50 - 2

            if node.id then
                if node.up ~= 0 then SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['up'][node.up], xOffset, yOffset + 32) end
                if node.down ~= 0 then SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['down'][node.down], xOffset, yOffset - 32 + 1) end
                if node.left ~= 0 then SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['left'][node.left], xOffset - 32, yOffset) end
                if node.right ~= 0 then SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['right'][node.right], xOffset + 32 + 1, yOffset) end
                if node.rightArrow ~= 0 then SetArrowTexture(tabIndex, TALENT_ARROW_TEXTURECOORDS['right'][node.rightArrow], xOffset + 16 + 5, yOffset) end
                if node.leftArrow ~= 0 then SetArrowTexture(tabIndex, TALENT_ARROW_TEXTURECOORDS['left'][node.leftArrow], xOffset - 16 - 5, yOffset) end
                if node.topArrow ~= 0 then SetArrowTexture(tabIndex, TALENT_ARROW_TEXTURECOORDS['top'][node.topArrow], xOffset, yOffset + 16 + 5) end
            else
                if node.up ~= 0 and node.down ~= 0 then
                    SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['up'][node.up], xOffset, yOffset)
                    SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['down'][node.down], xOffset, yOffset - 32)
                elseif node.left ~= 0 and node.right ~= 0 then
                    SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['right'][node.right], xOffset + 32, yOffset)
                    SetBranchTexture(tabIndex, TALENT_BRANCH_TEXTURECOORDS['left'][node.left], xOffset + 1, yOffset)
                end
            end
        end
    end
end

local function UpdateTreeBackground(tabIndex)
    local _, _, _, fileName
    if isPetMode then
        _, _, _, fileName = GetTalentTabInfo(tabIndex, false, true, 1)
    else
        _, _, _, fileName = GetTalentTabInfo(tabIndex)
    end
    local base = fileName and ('Interface\\TalentFrame\\' .. fileName .. '-') or 'Interface\\TalentFrame\\MageFire-'
    treeFrames[tabIndex].bgTopLeft:SetTexture(base .. 'TopLeft')
    treeFrames[tabIndex].bgTopRight:SetTexture(base .. 'TopRight')
    treeFrames[tabIndex].bgBottomLeft:SetTexture(base .. 'BottomLeft')
    treeFrames[tabIndex].bgBottomRight:SetTexture(base .. 'BottomRight')
end

Update = function()
    if not frame or not frame:IsVisible() then return end

    UpdatePetButton()
    UpdateSpecButtons()
    UpdatePreviewBar()

    local numTabs
    local currentButtons
    local tierPoints
    if isPetMode then
        numTabs = GetNumTalentTabs(false, true)
        currentButtons = petTalentButtons
        tierPoints = PET_TALENTS_PER_TIER
    else
        numTabs = 3
        currentButtons = playerTalentButtons
        tierPoints = PLAYER_TALENTS_PER_TIER
    end

    LayoutTreeFrames(numTabs)

    for tabIndex = 1, numTabs do
        local name, pointsSpent, previewPts
        if isPetMode then
            local _pts, _prev
            name, _, _pts, _, _prev = GetTalentTabInfo(tabIndex, false, true, 1)
            pointsSpent = _pts or 0
            previewPts  = _prev or 0
        else
            local _pts, _prev
            name, _, _pts, _, _prev = GetTalentTabInfo(tabIndex, false, false, currentTalentGroup)
            pointsSpent = _pts or 0
            previewPts  = _prev or 0
        end
        if name then
            treeFrames[tabIndex].header:SetText(name)
            treeFrames[tabIndex].pointsText:SetText((pointsSpent + previewPts) .. ' points')
            UpdateTreeBackground(tabIndex)
        end

        ResetBranches(tabIndex)

        local numTalents
        if isPetMode then
            numTalents = GetNumTalents(tabIndex, false, true)
        else
            numTalents = GetNumTalents(tabIndex)
        end

        for talentIndex = 1, numTalents do
            local buttonKey = tabIndex .. '_' .. talentIndex
            local button = currentButtons[buttonKey]
            if button then
                local talentName, iconTexture, tier, column, rank, maxRank
                if isPetMode then
                    talentName, iconTexture, tier, column, rank, maxRank =
                        GetTalentInfo(tabIndex, talentIndex, false, true, 1, previewMode)
                else
                    talentName, iconTexture, tier, column, rank, maxRank =
                        GetTalentInfo(tabIndex, talentIndex, false, false, currentTalentGroup, previewMode)
                end
                if talentName then
                    button.icon:SetTexture(iconTexture)
                    button.rank:SetText(rank .. '/' .. maxRank)

                    local cp
                    if isPetMode then
                        cp = GetUnspentTalentPoints(false, true, 1)
                    else
                        cp = GetUnspentTalentPoints(false, false, currentTalentGroup)
                    end
                    local tierUnlocked = ((tier - 1) * tierPoints <= pointsSpent)
                    local prereqsMaxed = CheckPrereqsMaxed(tabIndex, talentIndex, isPetMode)

                    if rank == maxRank then
                        button.border:SetVertexColor(1.0, 0.82, 0, 1.0)
                        button.icon:SetDesaturated(false)
                    elseif rank > 0 then
                        button.border:SetVertexColor(1.0, 0.82, 0, .4)
                        button.icon:SetDesaturated(false)
                    elseif prereqsMaxed and tierUnlocked and cp > 0 and rank < maxRank then
                        button.border:SetVertexColor(0.1, 1.0, 0.1, .3)
                        button.icon:SetDesaturated(false)
                    else
                        button.border:SetVertexColor(0.5, 0.5, 0.5)
                        button.icon:SetDesaturated(true)
                    end

                    button:Show()
                    branchArrays[tabIndex][tier][column].id = talentIndex

                    local forceDesaturated = (cp <= 0 and rank == 0) and 1 or nil
                    local tierUnlocked2 = ((tier - 1) * tierPoints <= pointsSpent) and 1 or nil
                    local prereqs
                    if isPetMode then
                        prereqs = {GetTalentPrereqs(tabIndex, talentIndex, false, true, 1)}
                    else
                        prereqs = {GetTalentPrereqs(tabIndex, talentIndex, false, false, currentTalentGroup)}
                    end
                    SetTalentPrereqs(tabIndex, tier, column, forceDesaturated, tierUnlocked2, unpack(prereqs))
                end
            end
        end
        DrawBranches(tabIndex)
    end

    local points
    if isPetMode then
        points = GetUnspentTalentPoints(false, true, 1)
        frame.headerText:SetText('Pet Talents')
        frame.pointsLeft:SetText('Pet Talent Points Available: |cFFFFFFFF' .. points .. '|r')
    else
        points = GetUnspentTalentPoints(false, false, currentTalentGroup)
        local specLabel = 'Talents'
        if GetNumTalentGroups() > 1 then
            specLabel = currentTalentGroup == 1 and 'Primary Spec' or 'Secondary Spec'
        end
        frame.headerText:SetText(specLabel)
        frame.pointsLeft:SetText('Talent Points Available: |cFFFFFFFF' .. points .. '|r')
    end
end

local function CreateAllTalents()
    local maxTier = 0
    for tabIndex = 1, 3 do
        local numTalents = GetNumTalents(tabIndex)
        for talentIndex = 1, numTalents do
            local name, _, tier, column = GetTalentInfo(tabIndex, talentIndex)
            if name then
                local button = CreateTalentButton(tabIndex, talentIndex, tier, column, false)
                playerTalentButtons[tabIndex .. '_' .. talentIndex] = button
                if tier > maxTier then maxTier = tier end
            end
        end
    end

    local treeH  = maxTier * 63 + 10
    local frameH = 50 + 50 + treeH + 60
    frame:SetHeight(frameH)
    for i = 1, 3 do
        treeFrames[i].frame:SetHeight(treeH)
        local bgH = treeH + 90
        local half = math.floor(bgH / 2)
        treeFrames[i].bgTopLeft:SetHeight(half)
        treeFrames[i].bgTopRight:SetHeight(half)
        treeFrames[i].bgBottomLeft:SetHeight(bgH - half)
        treeFrames[i].bgBottomRight:SetHeight(bgH - half)
    end
end

-- Called lazily on first switch to pet mode
CreatePetTalents = function()
    local numTabs = math.min(GetNumTalentTabs(false, true), 3)
    for tabIndex = 1, numTabs do
        local numTalents = GetNumTalents(tabIndex, false, true)
        for talentIndex = 1, numTalents do
            local name, _, tier, column = GetTalentInfo(tabIndex, talentIndex, false, true, 1)
            if name then
                local button = CreateTalentButton(tabIndex, talentIndex, tier, column, true)
                button:Hide()
                petTalentButtons[tabIndex .. '_' .. talentIndex] = button
            end
        end
    end
    petButtonsCreated = true
end

local function ToggleFrame()
    if not frame then
        CreateMainFrame()
        CreateTreeFrames()
        CreateAllTalents()
    end
    UpdatePetButton()
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        Update()
    end
end

-- Event frame for updates
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('CHARACTER_POINTS_CHANGED')
eventFrame:RegisterEvent('PLAYER_LEVEL_UP')
eventFrame:RegisterEvent('PLAYER_TALENT_UPDATE')
eventFrame:RegisterEvent('PET_TALENT_UPDATE')
eventFrame:RegisterEvent('UNIT_PET')
eventFrame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')
pcall(function()
    eventFrame:RegisterEvent('PREVIEW_TALENT_POINTS_CHANGED')
    eventFrame:RegisterEvent('PREVIEW_PET_TALENT_POINTS_CHANGED')
end)
eventFrame:SetScript('OnEvent', function(self, event, arg1)
    if event == 'UNIT_PET' then
        if arg1 == 'player' then
            -- Pet changed: old pet buttons are stale; discard and rebuild next time
            for _, btn in pairs(petTalentButtons) do btn:Hide() end
            petTalentButtons = {}
            petButtonsCreated = false
            lastLayoutNumTabs = -1  -- force layout recalc for new pet's tab count
            if isPetMode then
                isPetMode = false
            end
            UpdatePetButton()
            Update()
        end
    else
        Update()
    end
end)

ToggleTalentFrame = function()
    if UnitLevel('player') < 10 then return end
    if frame and frame:IsVisible() then pcall(PlaySound, 'TalentScreenClose') else pcall(PlaySound, 'TalentScreenOpen') end
    ToggleFrame()
    if UpdateMicroButtons then UpdateMicroButtons() end
end

if UpdateMicroButtons then
    local originalUpdateMicroButtons = UpdateMicroButtons
    UpdateMicroButtons = function()
        originalUpdateMicroButtons()
        if frame and frame:IsVisible() then
            if TalentMicroButton then TalentMicroButton:SetButtonState('PUSHED', 1) end
        else
            if TalentMicroButton then TalentMicroButton:SetButtonState('NORMAL') end
        end
        if DFRL and DFRL.menuframe and DFRL.menuframe:IsVisible() and MainMenuMicroButton then
            MainMenuMicroButton:SetButtonState('PUSHED', 1)
        end
    end
end

local talentFrameHooked = false
local function OverrideDefaultTalentFrame()
    -- Override the global called by the keybind and microbutton OnClick
    ToggleTalentFrame = function()
        if UnitLevel('player') < 10 then return end
        if frame and frame:IsVisible() then pcall(PlaySound, 'TalentScreenClose') else pcall(PlaySound, 'TalentScreenOpen') end
        ToggleFrame()
        if UpdateMicroButtons then UpdateMicroButtons() end
    end
    -- Override the sub-function Blizzard's ToggleTalentFrame delegates to,
    -- and that custom menus (e.g. DFRL) may call directly
    if PlayerTalentFrame_Toggle then
        PlayerTalentFrame_Toggle = function() ToggleTalentFrame() end
    end
    -- Hook the actual frame as a last resort (catches ShowUIPanel / direct Show calls).
    -- PlayerTalentFrame is the correct name; TalentFrame does not exist.
    if PlayerTalentFrame and not talentFrameHooked then
        talentFrameHooked = true
        PlayerTalentFrame:HookScript('OnShow', function(self)
            self:Hide()
            if not frame or not frame:IsVisible() then ToggleFrame() end
        end)
    end
end

local loader = CreateFrame('Frame')
loader:RegisterEvent('ADDON_LOADED')
loader:RegisterEvent('PLAYER_LOGIN')
loader:SetScript('OnEvent', function(self, event, addonName)
    if event == 'ADDON_LOADED' then
        if addonName == 'ImprovedTalents' then
            TALENTSVIEWER_SV = TALENTSVIEWER_SV or {}
            SV = TALENTSVIEWER_SV
        elseif addonName == 'Blizzard_TalentUI' then
            -- Blizzard_TalentUI loads lazily on first talent open; PlayerTalentFrame
            -- now exists, so we can hook it. This fires synchronously inside LoadAddOn,
            -- before the caller's subsequent ToggleTalentFrame/PlayerTalentFrame_Toggle call.
            OverrideDefaultTalentFrame()
        end
    elseif event == 'PLAYER_LOGIN' then
        -- Catches non-lazy load (Blizzard_TalentUI already loaded at startup)
        OverrideDefaultTalentFrame()
    end
end)
