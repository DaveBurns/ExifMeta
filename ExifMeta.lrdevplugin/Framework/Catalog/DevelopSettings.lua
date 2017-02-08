--[[
        DevelopSettings.lua

        Object that represents develop settings from a catalog point of view.
--]]


local DevelopSettings, dbg, dbgf = Object:newClass{ className = "DevelopSettings", register=true }


-- Constants for use with applies-to spec.
DevelopSettings.pvCodeLegacy = 1 -- PV2010 or PV2003.
DevelopSettings.pvCode2012 = 2   -- PV2012.
local pvLookup = { -- for when going through constraint method for lookup seems like overkill ;-}.
    ["5.0"] = { friendly="PV2003", pvCode = 1 },
    ["5.7"] = { friendly="PV2010", pvCode = 1 },
    ["6.6"] = { friendly="PV2012 (beta)", pvCode = 2 },
    ["6.7"] = { friendly="PV2012 (current)", pvCode = 2 },
}



--[[
        Note: @1/May/2012 only "writeable" fields are supported, i.e. those supported by cookmarks, dev-adjust, ...
            To use in dev-meta or whatever, they will need to be augmented.
        
        Field notes:
            * table key (string) setting ID in develop-settings table for photo(s).
            * friendly (string) Name for UI.
            * data-type (string) 'boolean', 'number', or 'string'.
            * constraints (optional table) may be required for numerics(???)
              * numeric: min, max
              * string: array of strings.
            * prereq (optional table) name and value of dependent (pre-requisite) setting. - so far, there has only been one of these.
              note: applies-to can be considered a pre-req...
            * appliesTo (number) defaults to "all PV". Bit mask indexed by PV.
            * group (string) for dividing in UI according to group.
            * subGroup (string) for further dividing in UI according to sub-group.
            * subName (string) name for setting when divided by sub-group.
            
        ###3 - consider constraining booleans too for friendly value.
--]]
DevelopSettings.table = { -- static table with all info for all settings.
    -- array of groups
    {   groupName="Basic",
        members={
            { id='AutoTone', friendly="Auto Tone", dataType='boolean' }, -- technically, auto-tone=false is not an adjustment. ###2, also auto-tone id is detected when looking for pre-reqs.
            { members = { groupName="Legacy Auto",
                { id='AutoExposure', friendly="Auto Exposure (Legacy)", dataType='boolean', appliesTo=1 },
                { id='AutoHighlightRecovery', friendly="Auto Highlight Recovery (Legacy)", dataType='boolean', appliesTo=1 }, -- ###3 works?
                { id='AutoShadows', friendly="Auto Shadows (Legacy)", dataType='boolean', appliesTo=1 },
                { id='AutoFillLight', friendly="Auto Fill Light (Legacy)", dataType='boolean', appliesTo=1 }, -- ###3?
                { id='AutoBrightness', friendly="Auto Brightness (Legacy)", dataType='boolean', appliesTo=1 },
                { id='AutoContrast', friendly="Auto Contrast (Legacy)", dataType='boolean', appliesTo=1 },
            }},
            { id='WhiteBalance', friendly="White Balance", dataType ='string', default='Custom', constraints={ "Custom", "As Shot", "Daylight", "Cloudy", "Shade", "Tungsten", "Fluorescent", "Flash", "Auto" } },
            { members = { -- anonymous sub-group
                { id='Temperature', friendly="Temperature (Raw)", dataType='number', baseAdj=50, constraints={ min=-10000, max=10000 }, prereq = { name='WhiteBalance', value='Custom' } }, -- ###3 @28/Sep/2013 9:33, these constraints seem wrong (don't want to fix without further investigation).
                { id='Tint', friendly="Tint (Raw)", dataType='number', constraints={ min=-100, max=100 }, prereq={ name='WhiteBalance', value='Custom' } },
                { id='IncrementalTemperature', friendly="Temperature (RGB)", dataType='number', constraints={ min=-100, max=100 }, prereq = { name='WhiteBalance', value='Custom' } }, -- for RGB files, not raw.
                { id='IncrementalTint', friendly="Tint (RGB)", dataType='number', constraints={ min=-100, max=100 }, prereq = { name='WhiteBalance', value='Custom' } }, -- for RGB files, not raw.
            }},
            { members = {
                { id='Exposure2012', friendly="Exposure (2012)", dataType='number', baseAdj=.1, constraints={ min=-5, max=5, precision=2 }, appliesTo=2 },
                { id='Contrast2012', friendly="Contrast (2012)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=2 }, 
                { id='Highlights2012', friendly="Highlights (2012)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=2 }, 
                { id='Shadows2012', friendly="Shadows (2012)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=2 }, 
                { id='Whites2012', friendly="Whites (2012)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=2 }, 
                { id='Blacks2012', friendly="Blacks (2012)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=2 }, 
            }},
            { members = { groupName = "Legacy Basics",
                { id='Exposure', friendly="Exposure (Legacy)", dataType='number', constraints={ min=-4, max=4, precision=2 }, appliesTo=1 }, 
                { id='HighlightRecovery', friendly="Highlight Recovery (Legacy)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=1 }, 
                { id='Shadows', friendly="Blacks (Legacy)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=1 }, 
                { id='FillLight', friendly="Fill Light (Legacy)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=1 }, 
                { id='Brightness', friendly="Brightness (Legacy)", dataType='number', constraints={ min=-150, max=150 }, appliesTo=1 }, 
                { id='Contrast', friendly="Contrast (Legacy)", dataType='number', constraints={ min=-50, max=100 }, appliesTo=1 }, 
                { id='Clarity', friendly="Clarity (Legacy)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=1 }, 
            }},
            { members = { -- anonymous sub-group (presence)
                { id='Clarity2012', friendly="Clarity (2012)", dataType='number', constraints={ min=-100, max=100 }, appliesTo=2 }, 
                { id='Vibrance', friendly="Vibrance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='Saturation', friendly="Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
        },
    },
    {   groupName = "Tone Curve",
        members={
            -- constraints are for absolute values, but relative sliders must be able to go incrementally negative too. ###2
            { id='ParametricShadowSplit', friendly="Parametric Shadow Split", dataType='number', relConstraint=0, constraints={ min=10, max=70 } }, 
            { id='ParametricMidtoneSplit', friendly="Parametric Midtone Split", dataType='number', relConstraint=0, constraints={ min=20, max=80 } }, 
            { id='ParametricHighlightSplit', friendly="Parametric Highlight Split", dataType='number', relConstraint=0, constraints={ min=30, max=90 } }, 
            -- rel-constraint=0 added 29/Nov/2014 4:13, which changes handling: ###1 document this.
            -- when applying a relative adjustment as part of a lr-dev-preset (when rel-constraint is 0), the splits are interpreted as absolute, not relative.
            
            { id='ParametricShadows', friendly="Parametric Shadows", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='ParametricDarks', friendly="Parametric Darks", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='ParametricLights', friendly="Parametric Lights", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='ParametricHighlights', friendly="Parametric Highlights", dataType='number', constraints={ min=-100, max=100 } }, 
        },
    },            
    {   groupName = "HSL",
        members={
            { members={ -- anonymous sub-group (hue)
                { id='HueAdjustmentRed', friendly="Red Hue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='HueAdjustmentOrange', friendly="Orange Hue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='HueAdjustmentYellow', friendly="Yellow Hue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='HueAdjustmentGreen', friendly="Green Hue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='HueAdjustmentAqua', friendly="Aqua Hue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='HueAdjustmentBlue', friendly="Blue Hue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='HueAdjustmentPurple', friendly="Purple Hue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='HueAdjustmentMagenta', friendly="Magenta Hue", dataType='number', constraints={ min=-100, max=100 } },
            }},
            { members={ -- sat
                { id='SaturationAdjustmentRed', friendly="Red Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='SaturationAdjustmentOrange', friendly="Orange Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='SaturationAdjustmentYellow', friendly="Yellow Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='SaturationAdjustmentGreen', friendly="Green Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='SaturationAdjustmentAqua', friendly="Aqua Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='SaturationAdjustmentBlue', friendly="Blue Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='SaturationAdjustmentPurple', friendly="Purple Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='SaturationAdjustmentMagenta', friendly="Magenta Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
            { members={
                { id='LuminanceAdjustmentRed', friendly="Red Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='LuminanceAdjustmentOrange', friendly="Orange Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='LuminanceAdjustmentYellow', friendly="Yellow Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='LuminanceAdjustmentGreen', friendly="Green Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='LuminanceAdjustmentAqua', friendly="Aqua Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='LuminanceAdjustmentBlue', friendly="Blue Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='LuminanceAdjustmentPurple', friendly="Purple Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='LuminanceAdjustmentMagenta', friendly="Magenta Luminance", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
        },
    },
    {   groupName = "B&&W",
        members={
            { id='ConvertToGrayscale', friendly="Convert to Black && White", dataType = 'boolean' },
            { id='EnableGrayscaleMix', friendly="Enable Black && White", dataType = 'boolean' }, -- Note: this is the section enable/disable! ###3 (this should be deleted, once scope if impact has been evaluated).
            { members={
                { id='AutoGrayscaleMix', friendly="B&&W Auto", dataType = 'boolean' },
                { id='GrayMixerRed', friendly="B&&W Red", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrayMixerOrange', friendly="B&&W Orange", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrayMixerYellow', friendly="B&&W Yellow", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrayMixerGreen', friendly="B&&W Green", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrayMixerAqua', friendly="B&&W Aqua", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrayMixerBlue', friendly="B&&W Blue", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrayMixerPurple', friendly="B&&W Purple", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrayMixerMagenta', friendly="B&&W Magenta", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
        },
    },
    {   groupName = "Split Toning",
        members={
            { id='SplitToningHighlightHue', friendly="Split Toning Highlight Hue", dataType='number', relConstraint=0, constraints={ min=-360, max=360 } }, 
            { id='SplitToningHighlightSaturation', friendly="Split Toning Highlight Saturation", dataType='number', constraints={ min=0, max=100 } }, 
            { id='SplitToningBalance', friendly="Split Toning Balance", dataType='number', relConstraint=0, constraints={ min=0, max=100 } }, 
            { id='SplitToningShadowHue', friendly="Split Toning Shadow Hue", dataType='number', relConstraint=0, constraints={ min=-360, max=360 } }, 
            { id='SplitToningShadowSaturation', friendly="Split Toning Shadow Saturation", dataType='number', constraints={ min=0, max=100 } }, 
        },
    },
    {   groupName = "Detail",
        members={
            { members={ -- sharpness sub-group
                { id='Sharpness', friendly="Sharpening Amount", dataType='number', constraints={ min=0, max=100 } }, 
                { id='SharpenRadius', friendly="Sharpening Radius", dataType='number', baseAdj=.1, constraints={ min=.5, max=3, precision=1 } }, 
                { id='SharpenDetail', friendly="Sharpening Detail", dataType='number', constraints={ min=0, max=100 } }, 
                { id='SharpenEdgeMasking', friendly="Sharpening Masking", dataType='number', constraints={ min=0, max=100 } }, 
            }},
            { members={ -- noise
                { id='LuminanceSmoothing', friendly="Luminance NR", dataType='number', constraints={ min=0, max=100 } }, 
                { id='LuminanceNoiseReductionDetail', friendly="Luminance NR Detail", dataType='number', constraints={ min=0, max=100 } }, 
                { id='LuminanceNoiseReductionContrast', friendly="Luminance NR Contrast", dataType='number', constraints={ min=0, max=100 } }, 
                { id='ColorNoiseReduction', friendly="Color NR", dataType='number', constraints={ min=0, max=100 } }, 
                { id='ColorNoiseReductionDetail', friendly="Color NR Detail", dataType='number', constraints={ min=0, max=100 } },
                { id='ColorNoiseReductionSmoothness', friendly="Color NR Smoothness", dataType='number', constraints={ min=0, max=100 } },
            }},
            
        },
    },
    {   groupName = "Lens Corrections",
        members = {
            { members={ -- profile-based
                -- { id='LensProfileEnable', friendly="Lens Profile Enable", dataType='number', constraints={ 0, 1 }, -- until 5/Feb/2013 17:56 ###2 expected in some contexts, no doubt.
                { id='LensProfileEnable', friendly="Lens Profile Enable", dataType='number', default=1, constraints={ { title="Disable", value=0 }, { title="Enable", value=1 } } }, -- @5/Feb/2013 17:56 
                { id='LensProfileSetup', friendly="Lens Profile Setup", dataType = 'string' }, -- constraints = "LensDefaults", -- ###3
                -- @28/Sep/2013 12:17 - Make & Model are neither settable nor readable by plugin.
                { id='LensProfileName', friendly="Lens Profile Name", dataType ='string', prereq = { name='LensProfileEnable', value=1 } }, -- "Adobe (Canon PowerShot G12)", -- ###3
                { id='LensProfileFilename', friendly="Lens Profile Filename", dataType ='string', prereq = { name="LensProfileEnable", value=1 } },-- , "Canon PowerShot G12 - RAW.lcp", -- ###3
                { id='LensProfileDistortionScale', friendly="Lens Profile Distortion Scale", dataType='number', constraints={ min=-100, max=100 } }, 
                --{ id='LensProfileDistortionScale', friendly="Lens Profile Distortion Scale", dataType='number', constraints={ min=-100, max=100 } }, - dup discovered 5/Feb/2013 18:05 - check cookmarks..
                { id='LensProfileVignettingScale', friendly="Lens Profile Vignetting Amount", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
            { members={ -- color
                { id='AutoLateralCA', friendly="Remove Chromatic Aberration", dataType='number', default=1, constraints={ { title="Disable", value=0 }, { title="Enable", value=1 } } }, 
                { id='DefringePurpleAmount', friendly="Defringe Purple Amount", dataType='number', constraints={ min=0, max=20 } },            
                { id='DefringePurpleHueLo', friendly="Defringe Purple Hue - Low", dataType='number', constraints={ min=0, max=90 } },            
                { id='DefringePurpleHueHi', friendly="Defringe Purple Hue - High", dataType='number', constraints={ min=10, max=100 } },       
                { id='DefringeGreenAmount', friendly="Defringe Green Amount", dataType='number', constraints={ min=0, max=20 } },            
                { id='DefringeGreenHueLo', friendly="Defringe Green Hue - Low", dataType='number', constraints={ min=0, max=90 } },            
                { id='DefringeGreenHueHi', friendly="Defringe Green Hue - High", dataType='number', constraints={ min=10, max=100 } },
            }},
            { members={ -- manual
                { id='LensManualDistortionAmount', friendly="Lens Manual Distortion Amount", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='PerspectiveVertical', friendly="Lens Manual Perspective Vertial", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='PerspectiveHorizontal', friendly="Perspective Horizontal", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='PerspectiveRotate', friendly="Perspective Rotate", dataType='number', constraints={ min=-360, max=360 } }, 
                { id='PerspectiveScale', friendly="Lens Manual Perspective Scale", dataType='number', constraints={ min=-200, max=200 } }, 
                { id='CropConstrainToWarp', friendly="Lens Manual Contrain To Warp", dataType='number', constraints={ { title="Disable", value=0 }, { title="Enable", value=1 } } },
                { id='VignetteMidpoint', friendly="Lens Manual Vignette Midpoint", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='VignetteAmount', friendly="Lens Manual Vignette Amount", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
        }            
    },
    {   groupName = "Effects",
        members = {
            { members={ -- post-crop vignetting
                { id='PostCropVignetteStyle', friendly="Post-crop Vignette Style", dataType='number', default=1, constraints={ { title="Paint", value=0 }, { title="HighlightPriority", value=1 }, { title="Color Priority", value=2 } } },
                { id='PostCropVignetteAmount', friendly="Post-crop Vignette Amount", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='PostCropVignetteMidpoint', friendly="Post-crop Vignette Midpoint", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='PostCropVignetteRoundness', friendly="Post-crop Vignette Roundness", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='PostCropVignetteFeather', friendly="Post-crop Vignette Feather", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='PostCropVignetteHighlightContrast', friendly="Post-crop Vignette Highlights", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
            { members={ -- grain
                { id='GrainAmount', friendly="Grain Amount", dataType='number', constraints={ min=-100, max=100 } }, 
                { id='GrainSize', friendly="Grain Size", dataType='number', constraints={ min=0, max=100 } }, 
                { id='GrainFrequency', friendly="Grain Roughness", dataType='number', constraints={ min=-100, max=100 } }, 
            }},
        },
    },
    {   groupName = "Camera Calibration",
        members = {
            { id='ProcessVersion', friendly="Process Version", dataType = 'string', default='6.7', constraints={ { title="PV2003", value="5.0" }, { title="PV2010", value="5.7" }, { title="PV2012 (Beta)", value="6.6" }, { title="PV2012 (Current)", value="6.7" } } },
            { id='CameraProfile', friendly="Camera Profile", dataType = 'string', default='Adobe Standard' }, -- constraints = "Canon PowerShot G12 Adobe Standard (RC Debright)", -- ###3
            { id='ShadowTint', friendly="Camera Calibration Shadow Tint", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='RedHue', friendly="Primary Red Hue", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='RedSaturation', friendly="Primary Red Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='GreenHue', friendly="Primary Green Hue", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='GreenSaturation', friendly="Primary Green Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='BlueHue', friendly="Primary Blue Hue", dataType='number', constraints={ min=-100, max=100 } }, 
            { id='BlueSaturation', friendly="Primary Blue Saturation", dataType='number', constraints={ min=-100, max=100 } }, 
        },
    },
    {   groupName = "Enable/Disable Groups",
        members = {
            { id='EnableToneCurve', friendly="Enable Tone Curve", dataType = 'boolean' }, -- not working in snapshots, but @Lr4.4RC1 - working via plugin.
            { id='EnableColorAdjustments', friendly="Enable HSL Adjustments", dataType = 'boolean' }, 
            -- { id='EnableGrayscaleMix', friendly="Enable Black && White", dataType = 'boolean' }, -- Note: this is the same as enable-color-adjustments when it's b&w - inadvertently (and wrongly) replicated in another section, which is why it's commented out here - I don't want to foul something up without further investigation.
            { id='EnableSplitToning', friendly="Enable Split Toning", dataType = 'boolean' },
            { id='EnableDetail', friendly="Enable Detail", dataType = 'boolean' }, 
            { id='EnableLensCorrections', friendly="Enable Lens Corrections", dataType = 'boolean' }, 
            { id='EnableEffects', friendly="Enable Effects", dataType = 'boolean' }, 
            { id='EnableCalibration', friendly="Enable Camera Calibration", dataType = 'boolean' },
            { members={            
                { id='EnableRetouch', friendly="Enable Retouch", dataType = 'boolean' }, 
                { id='EnableRedEye', friendly="Enable Red-eye", dataType = 'boolean' }, 
                { id='EnableGradientBasedCorrections', friendly="Enable Linear Gradients", dataType = 'boolean' }, 
                { id='EnableCircularGradientBasedCorrections', friendly="Enable Circular Gradients", dataType = 'boolean' }, -- added 28/Sep/2013 - untested.
                { id='EnablePaintBasedCorrections', friendly="Enable Paint", dataType = 'boolean' }, 
            }},
        },
    },
    {   groupName = nil, -- "Unsupported in Lr4",
        members = {
            -- { id='LensProfileChromaticAberrationScale', friendly="Auto Tone", dataType='number', constraints={ min=-200, max=200 } }, 
            -- { id='ChromaticAberrationB', friendly="CA Blue", dataType='number', constraints={ min=-100, max=100 }, appliesTo=0 }, -- no longer supported in Lr4, for any PV.
            -- { id='ChromaticAberrationR', friendly="CA Red", dataType='number', constraints={ min=-100, max=100 } }, 
            -- { id='Defringe', friendly="Defringe", dataType='number', constraints={ min=0, max=2 } }, 
        },
    },                        
    {   groupName = nil, -- "Unsupported by Adobe",
        members = {
            --    orientation = "AB",
            --    CropLeft = { min=-10000, max=10000, appliesTo=0 },  -- no sirve...
            --    CropAngle = { min=-1000, max=1000, appliesTo=0 }, -- no sirve...
            --    CropBottom = { dataType='number', constraints={ min=-10000, max=10000 } }, 
            --    CropRight = { dataType='number', constraints={ min=-10000, max=10000 } }, 
            --    CropTop = { dataType='number', constraints={ min=-10000, max=10000 } }, 
        },
    },                        
    {   groupName = nil, -- "Unsupported by Elare Plugin Framework",
        members = {
            --    ToneCurveName2012 = { dataType = 'string' }, -- constraints = "Custom", -- ###2 - not working? - Don't need to manipulate the name directly, maybe - seems just setting parameters or points will do it.
            --    ToneCurveName = { dataType ='string', constraints={ "Medium Contrast", "Linear", "Strong Contrast" }, appliesTo=1 }, -- Could be custom name too. ###2 - not working.
            --[[    ToneCurve = { -- legacy
                    [1] = 0, 
                    [2] = 0, 
                    [3] = 32, 
                    [4] = 22, 
                    [5] = 64, 
                    [6] = 56, 
                    [7] = 128, 
                    [8] = 128, 
                    [9] = 192, 
                    [10] = 196, 
                    [11] = 255, 
                    [12] = 255}, --]]
            --[[    ToneCurvePV2012Red = {
                    [1] = 0, 
                    [2] = 0, 
                    [3] = 255, 
                    [4] = 255}, --]]
            --    RedEyeInfo = { }, - not supported
            --    RetouchInfo = {}, 
            --[[    ToneCurvePV2012 = {
                    [1] = 0, 
                    [2] = 0, 
                    [3] = 120, 
                    [4] = 113, 
                    [5] = 255, 
                    [6] = 255}, --]]
            --[[    ToneCurvePV2012Green = {
                    [1] = 0, 
                    [2] = 0, 
                    [3] = 255, 
                    [4] = 255}, --]]
            --[[    ToneCurvePV2012Blue = {
                    [1] = 0, 
                    [2] = 0, 
                    [3] = 255, 
                    [4] = 255}, --]]
        },
    },
    {   groupName = nil, -- "Unsupported",
        members = {
            --    LensProfileDigest = "973B26A8CCE61821111161707E048A48", 
        },
    }, 
}


--- Constructor for extending class.
--
function DevelopSettings:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage      Singleton for interfacing to develop settings subsystem.
--  @usage      You must initialize instance in init.lua - as of 30/May/2014, not part of framework by default.
--
--  @param      t   Starter table, with optional member: 'cleanup' - set true to have temporary plugin develop presets from *last* time deleted.
--
function DevelopSettings:new( t )
    local o = Object.new( self, t )
    o.applyAdjGate = Gate:new{ max=20 } -- gated access to apply adjustments.
    o.assurePrereqsGate = Gate:new{ max=20 } -- gated access to apply adjustments.
    o:_init() -- init settings lookup and item list.
    if o.cleanup then
        local presets = LrApplication.getDevelopPresetsForPlugin( _PLUGIN ) -- hopefully no need to yield.
        for _, preset in ipairs( presets ) do
            local file = preset:getFile()
            if fso:existsAsFile( file ) then
                LrFileUtils.delete( file )
            end
        end
    end    
    return o
end



--- initialize develop preset cache.
--
--  @usage initialize at the beginnig of each "run" when you'll be looking up user (not plugin) develop presets.
--
function DevelopSettings:initUserPresets()
    self.userPresetLookup = {} -- lookup preset by name.
    for i, v in ipairs( LrApplication.developPresetFolders() ) do
        for j, preset in ipairs( v:getDevelopPresets() ) do
            self.userPresetLookup[preset:getName()] = preset
        end
    end
end



--- forces re-init of dev-cache if warranted when init-ing settings.
--
--  @usage - you can call this, then cache will be auto-initialized upon first use, or initialize explicitly.. - your call.
--
function DevelopSettings:clearUserPresetCache()
    self.userPresetLookup = nil
end



--- Get Lr preset object based on preset (leaf) name.
--
--  @usage @4/Apr/2014 20:45 only used by Ottomanic Importer.
--
function DevelopSettings:getUserPreset( name )
    if not self.userPresetLookup then
        self:initUserPresets()
    end
    return self.userPresetLookup[name]
end



--- Get develop setting specifications table.
--
--  @usage call this method insted of accessing dev-set table directly, since in future, it's format may change, but this method will still return the same thing.
--
function DevelopSettings.getSpecTable()
    return DevelopSettings.table
end



--- Get friendly setting name given specified setting id.
--
--  @param id adjustment ID
--
--  @return title should never be empty, and will never be nil (echos ID if not found in lookup table).
--
function DevelopSettings:getFriendlySettingName( id )
    if self.settingLookup[id] then
        return self.settingLookup[id].friendly or id
    else
        --Debug.pause( id ) - ###2 these should be present in table too, but Cookmarks may need a tweak.
        return str:to( id )
    end
end



-- private method to populate setting-lookup table and popup-items array.
function DevelopSettings:_init()
    self.settingLookup = {}
    self.popupItems = {}
    local function add( item )
        if item.appliesTo == 0 then
            return
        end
        self.settingLookup[item.id] = item
        local pItem = { title=item.friendly, value=item }
        self.popupItems[#self.popupItems + 1] = pItem
    end
    -- note: as currently implemented, group hierarchy is limited to 2 levels (groups and 1 level of sub-groups only).
    for i, group in ipairs( DevelopSettings.table ) do
        repeat
            if group.groupName == nil then -- not a real group, more of a place holder / reminder..
                break -- convenience
            end
            if group.members == nil then -- a group with no members is like a dead puppy: not much fun..
                app:error( "group sans members" )
                -- break
            end
            -- process group members:
            for j, member in ipairs( group.members ) do
                if member.id then -- member is a develop setting item.
                    add( member )
                else -- member is another group (a sub-group).
                    local pItem = { separator=true }
                    self.popupItems[#self.popupItems + 1] = pItem
                    for ii, submember in ipairs( member.members ) do
                        add( submember )
                    end
                    local pItem = { separator=true }
                    self.popupItems[#self.popupItems + 1] = pItem
                end
            end
            self.popupItems[#self.popupItems + 1] = { separator=true }
        until true
    end
    if self.popupItems[#self.popupItems].separator then
        self.popupItems[#self.popupItems] = nil -- kill extraneous separator.
    end
end



--- Get popup according to specified stipulation (process version - internal string representation).
--
--  @param pv (string) process version - if nil, any pv will do, otherwise constrained..
--
--  @return items - titles are friendly, values are items (as seen in dev-sets table at top of this module).
--
function DevelopSettings:getPopupMenuItems( pv )
    if pv == nil then -- get all items, regardless of pv.
        return self.popupItems
    else -- restrict to those supported by specified pv.
        local cuz = {}
        local sep = false
        for i, item in ipairs( self.popupItems ) do
            if item.value ~= nil then
                if item.value.appliesTo ~= nil then
                    if item.value.appliesTo == pv then
                        cuz[#cuz + 1] = item
                        sep = false
                    -- else
                    end
                else
                    cuz[#cuz + 1] = item
                    sep = false
                end
            else -- include separators
                if not sep then -- protect from 2 successive separators, in case a group or sub-group is empty.
                    cuz[#cuz + 1] = item
                    sep = true
                end
            end
        end
        if sep then
            cuz[#cuz] = nil -- kill extraneous separator.
        end
        return cuz
    end
end



--- Get lookup table for setting ID to setting spec.
--
--  @usage Get lookup table using this method instead of direct access, for future-proofing.
--
function DevelopSettings:getLookup()
    return self.settingLookup
end



--- Get item from lookup table.
--
function DevelopSettings:getItem( id )
    return self.settingLookup[id]
end



--- Get process version code from specified develop settings.
--
--  @param devSettings - the whole sha-bango as obtained from photo.
--
--  @return pvCode which can be used in other methods which have pv-code param..
--
function DevelopSettings:getPvCode( devSettings )
    local pvCode
    if str:getChar( devSettings['ProcessVersion'], 1 ) == '6' then
        pvCode = DevelopSettings.pvCode2012
    else
        pvCode = DevelopSettings.pvCodeLegacy
    end
    return pvCode
end



--- Determine if specified setting applies to specified process version (see codes above)
--
--  @usage if id in table, then response is definitive; if not in table, it assumes the setting *is* applicable - take care if care needs taking..
--
function DevelopSettings:appliesTo( id, pvCode )
    local it = self.settingLookup[id]
    if it then -- is "registered" (is in table).
        if it.appliesTo == nil or it.appliesTo == pvCode then -- either applies to all (is unqualified), or applies to specific pv.
            return true
        else -- definitely N/A.
            return false
        end
    else
        return true -- note: dev settings lookup table is not 100% complete, so one must assume if not present then id nevertheless applies, and just isn't "registered".
        -- if id came from real dev settings, that'll be true, if user/ui: not necessarily...
    end
end



--- Adjust specified settings.
--
--  @param photos (array of LrPhoto, reauired) photos to adjust.
--  @param undoTitle (string, reauired) alias: presetName.
--  @param ments (table, required) adjust-ments to make, as a table of name/value pairs.
--  @param tmo (number, default=10) seconds to wait for catalog - ignored if already has write access.
--
--  @usage This wrapper to roll adjustments into a preset and optionally wrap for catalog access - does *NOT* assure pre-requisites..
--  @usage synchronous - must be called from async task.
--
--  @return status
--  @return message
--
function DevelopSettings:adjustPhotos( photos, undoTitle, ments, tmo )
    return app:call( Call:new{ name=undoTitle, async=false, main=function( call )
        local function adjust()
            local preset = LrApplication.addDevelopPresetForPlugin( _PLUGIN, undoTitle, ments )
            if preset then
                app:logVerbose( "\"Added\" new or changed develop preset for plugin: ^1", undoTitle )
            else
                error( "No preset" )
            end
            for i, photo in ipairs( photos ) do
                photo:applyDevelopPreset( preset, _PLUGIN )
            end
        end
        if catalog.hasWriteAccess then
            adjust()
        else
            local s, m = cat:update( tmo or 10, call.name, adjust )
            if not s then
                error( m ) -- caught and returned as status/message.
            end
        end
    end } )
end



--- Transfer adjustments from one photo to one or more photos, those supported by SDK only (does not support Crop & Orientation - see Xmp:transferDevelopAdjustments).
--
--  @param params (array of parameters, reauired) thusly:<br>
--      metadataCache (LrMetadata cache, optional) if passed, be sure to include raw ids: path, isVirtualCopy, and fmt id: copyName.<br>
--      fromPhoto (LrPhoto, reauired) source photo.
--      toPhoto (LrPhoto *or* array of them, required) target photo(s).
--      exclusions (table, default=nil) set of dev-setting names to be excluded, otherwise none will be excluded.
--      inclusions (table, default=nil) set of dev-setting names to be included *** note: it's an error if exclusions are passed too. if inclusions not passed, all will be included unless excluded.
--      timeout (number, default=10) number of seconds to contend for catalog access - ignored if pre-wrapped.
--      exifToolSession (ExifToolSession, default=nil) not yet implemented, if passed, exiftool will be used to transfer settings via xmp, instead of sdk. Will require metadata read upon return.
--
--  @usage Does *NOT* assure pre-requisites, nor consider pv mismatching.
--  @usage will wrap with catalog accessor if need be - recommend pre-wrapping if multiple target photos, or done in a loop with a bunch of source photos.
--  @usage synchronous - must be called from async task.
--
--  @return status (boolean) true iff aok, otherwise false/nil.
--  @return message (string) error message - only if not aok.
--
function DevelopSettings:transferAdjustments( params )
    -- load all params:
    local cache = params.metadataCache
    local fromPhoto = params.fromPhoto or error( "no from photo" )
    local toPhotos = params.toPhoto or error( "no to photo(s)" )
    local tmo = params.timeout or 10
    if toPhotos.getRawMetadata then -- single photo
        toPhotos = { toPhotos } -- convert to array.
    end
    local inclDev = params.inclusions -- not mandatory
    local exclDev = params.exclusions -- not mandatory
    local fromName = cat:getPhotoNameDisp( fromPhoto, false, cache )
    local fromDev = self:getDevelopSettings( fromPhoto )
    local toDev
    if not tab:isEmpty( exclDev ) then
        assert( tab:isEmpty( inclDev ), "do not pass both exclusions and inclusions" )
        toDev = {}
        for k, v in pairs( fromDev ) do
            if not exclDev[k] then
                toDev[k] = fromDev[k]
            end
        end
    elseif not tab:isEmpty( inclDev ) then
        toDev = {}
        for k, v in pairs( fromDev ) do
            if inclDev[k] then
                toDev[k] = fromDev[k]
            end
        end
        -- Debug.lognpp( toDev )
    else
        toDev = fromDev
    end
    local s, m = developSettings:adjustPhotos( toPhotos, str:fmtx( "Adjustments From ^1", fromName ), toDev, tmo )
    return s, m
end



--- Assures pre-requisites are met for specified photo, specified adjustment.
--
--  @usage this is generally called when building relatively adjusted photo settings table, to avoid missing relative adjustments due to lack of existing setting.<br>
--         Some methods also have built-in pre-req assurance, but that may be after-the-fact in the afore-mentioned case.
--  @usage this gains access to catalog, makes adjustment, then commits it (exists catalog accessor), and sleeps, for *each* adjustment to *each* photo.<br>
--         and so it is not a speed demon, to say the least. But I've yet to figure out a reliable settling algorithm that handles all cases.
--
--  @param photo    lr-photo
--  @param id       dev-settings ID, which may or may not have pre-requisites (will be auto-determined by this method).
--  @param tmo      catalog access timeout number in seconds - optional: default is 10.
--
--  @return status (boolean) nil => error: see message; true => pre-req assured, no message accompaniment; false => no pre-req assurance need be satisfied for setting - see message for verbose logging...
--  @return message (string) error or qualifying message, depending on status.
--
function DevelopSettings:assurePrereqs( photo, id, tmo )
    return app:call( Call:new{ name="Assure Dev Pre-requisites", main=function( call )
        assert( not catalog.hasWriteAccess, "do not wrap in catalog accessor" )
        local s, m = self.assurePrereqsGate:enter()
        if not s then error( m ) end
        local lookup = self.settingLookup[id]
        local prereq = lookup.prereq
        if prereq ~= nil then
            local dev = self:getDevelopSettings( photo ) -- probably not optimally efficient. ###2
            if dev[prereq.name] == prereq.value then
                -- good to go
                return false, str:fmtx( "Pre-requisite already satisfied for ^1: ^2=^3", id, prereq.name, prereq.value )
            else
                local set = {}
                set[prereq.name] = prereq.value
                local name = str:fmt( "Prerequisite: ^1=^2", prereq.name, prereq.value )
                local preset = LrApplication.addDevelopPresetForPlugin( _PLUGIN, name, set ) -- let it auto-append a uniqueness id if need be.
                if preset then
                    local s, m = cat:update( tmo or 10, "Assure Prereq", function( context, phase )
                        photo:applyDevelopPreset( preset, _PLUGIN )
                        app:logv( "Applied pre-requisite - ^1", name )
                    end )
                    if s then
                        local wait = app:getPref( 'settlingTimePerOp' ) or 3
                        app:sleep( wait )
                        app:logv( "Waited ^1 seconds for ^2 to settle", wait, name )
                        return true
                    else
                        return nil, m
                    end
                else
                    app:error( "No preset" )
                end
            end
        else
            -- Debug.logn( "No pre-req" )
        end
        return false, str:fmtx( "No pre-requisite specified for ^1", id )
    end, finale=function( call )
        self.assurePrereqsGate:exit()
    end } )
end



--- for constraining individual settings whilst building.
--
--  @usage this module supports constraining externally or internally, so far I usually constrain externally, using this method - your call though..
--  @usage can also be used for looking up friendly name (title) for (enum) value.
--
function DevelopSettings:constrainSetting( id, value )
    local lookup = self.settingLookup[id]
    if lookup then
        local c = self.settingLookup[id].constraints
        if c then
            if c.min then
                app:assert( type( value ) == 'number', "'^1' should be a number, not a '^2'", id, type( value ) ) -- perhaps overkill, but values may come from advanced settings and this may help shed light on mistakes.
                if value < c.min then
                    return c.min, c.min
                end
            end
            if c.max then
                -- note: there are no constraints having max that don't also have min, so checking type again here is redundent (barring some constraint editing error...).
                if value > c.max then
                    return c.max, c.max
                else
                    return value, value
                end
            end
            if c[1] then
                if c[1].title then
                    for i, v in ipairs( c ) do
                        if value == v.value then
                            return value, v.title
                        end
                    end
                    return value, nil
                else -- constraints is list of acceptable values.
                    for i, v in ipairs( c ) do
                        if value == v then
                            return value, value
                        end
                    end
                    return value, nil
                end
            end
        else -- no constraints
            return value, value
        end
    else
        dbgf( "Un-registered dev setting passing through unfettered: ^1", id )
    end
    return value, value -- presently assuming non-range-based settings are pre-constrained (e.g. via UI).
end



-- consider constraining whilst building instead.
function DevelopSettings:constrainSettings( settings )
    local new = {}
    for k, v in pairs( settings ) do
        new[k] = self:constrainSetting( k, v )
    end
    return new -- added 14/Feb/2014 3:18, which means prior to this: not-pre-constrained in calling context was not working - not sure usage ###2.
end



--- Assures PV2012 settings are settled, generally after auto-tone applied, presumably in calling context.
--
--  @usage Could also be called to assure photo has settled after changing process version.
--
--  @param photo (LrPhoto, required)
--  @param dev (table, optional) Initial develop settings, if already available in calling context.
--  @param tmo (number, default=6) Number of seconds to allow for settling. Note - actual time required may depend on number of photos recently adjusted which have to settle.
--  @param atFlag (boolean, default=false) 
--
--  @return develop settings, once settled.
--  @return error message, if unsettleable.
--
function DevelopSettings:assurePv2012BasicSettings( photo, dev, tmo, atFlag, expSettings )
    local maxCount
    if tmo == nil then
        maxCount = 100 -- 10 seconds - should be plenty for one photo.
    else
        maxCount = tmo * 10 -- (1/10 seconds per count). use this mode for >1 photos needing to settle (be careful - maybe not the best practice..).
    end
    local count = 1
    local dev2 = dev or self:getDevelopSettings( photo )
    if str:getFirstChar( dev2.ProcessVersion ) ~= '6' then
        local rawValue, fmtValue = self:constrainSetting( 'ProcessVersion', dev2.ProcessVersion )
        fmtValue = fmtValue or rawValue
        return dev2, str:fmtx( "PV2012 basic settings do not apply to photos whose process version is '^1'.", fmtValue )
    end
    local steadyState
    repeat
        repeat
            if dev2.Exposure2012 == nil or dev2.Exposure2012 < -5 or dev2.Exposure2012 > 5 then break end
            if dev2.Contrast2012 == nil or dev2.Contrast2012 < -100 or dev2.Contrast2012 > 100 then break end
            if dev2.Highlights2012 == nil or dev2.Highlights2012 < -100 or dev2.Highlights2012 > 100 then break end
            if dev2.Shadows2012 == nil or dev2.Shadows2012 < -100 or dev2.Shadows2012 > 100 then break end
            if dev2.Whites2012 == nil or dev2.Whites2012 < -100 or dev2.Whites2012 > 100 then break end
            if dev2.Clarity2012 == nil or dev2.Clarity2012 < -100 or dev2.Clarity2012 > 100 then break end -- auto-toning does not affect clarity, so this is a don't care in case
            if dev2.Blacks2012 == nil or dev2.Blacks2012 < -100 or dev2.Blacks2012 > 100 then break end
            -- of auto-toning, granted if setting for it are outside legal values, they're not settled yet.
            -- Note: not checking for tone-curve-2012... - must be done independently if need be.
            if atFlag then
                if dev2.Blacks2012 > 25 then
                    app:logv( "PV2012 blacks are ^1 (after ^2 checks)", dev2.Blacks2012, count )
                else
                    app:logv( "PV2012 basic (auto-toned) settings are all in bounds (after ^1 checks)", count )
                end
            else
                app:logv( "PV2012 basic settings are all in bounds (after ^1 checks)", count )
            end
            -- fall-through => in bounds
            if expSettings then
                if expSettings.Exposure2012 and not num:isWithin( dev2.Exposure2012, expSettings.Exposure2012, .01 ) then break end
                if expSettings.Contrast2012 and not num:isWithin( dev2.Contrast2012, expSettings.Contrast2012, 1 ) then break end
                if expSettings.Highlights2012 and not num:isWithin( dev2.Highlights2012, expSettings.Highlights2012, 1 ) then break end
                if expSettings.Shadows2012 and not num:isWithin( dev2.Shadows2012, expSettings.Shadows2012, 1 ) then break end
                if expSettings.Whites2012 and not num:isWithin( dev2.Whites2012, expSettings.Whites2012, 1 ) then break end
                if expSettings.Blacks2012 and not num:isWithin( dev2.Blacks2012, expSettings.Blacks2012, 1 ) then break end
                if expSettings.Clarity2012 and not num:isWithin( dev2.Clarity2012, expSettings.Clarity2012, 1 ) then break end
                app:logv( "PV2012 basic settings are all as expected (after ^1 checks)", count )
                return dev2
            elseif steadyState then
                repeat
                    if not num:isWithin( dev2.Exposure2012, steadyState.Exposure2012, .01 ) then app:logV( "Exposure changed from ^1 to ^2", steadyState.Exposure2012, dev2.Exposure2012 ); break; end
                    if not num:isWithin( dev2.Contrast2012, steadyState.Contrast2012, 1 ) then app:logV( "Contrast changed from ^1 to ^2", steadyState.Contrast2012, dev2.Contrast2012 ); break; end
                    if not num:isWithin( dev2.Highlights2012, steadyState.Highlights2012, 1 ) then app:logV( "Highlights changed from ^1 to ^2", steadyState.Highlights2012, dev2.Highlights2012 ); break; end
                    if not num:isWithin( dev2.Shadows2012, steadyState.Shadows2012, 1) then app:logV( "Shadows changed from ^1 to ^2", steadyState.Shadows2012, dev2.Shadows2012 ); break; end
                    if not num:isWithin( dev2.Whites2012, steadyState.Whites2012, 1 ) then app:logV( "Whites changed from ^1 to ^2", steadyState.Whites2012, dev2.Whites2012 ); break; end
                    if not num:isWithin( dev2.Blacks2012, steadyState.Blacks2012, 1 ) then app:logV( "Blacks changed from ^1 to ^2", steadyState.Blacks2012, dev2.Blacks2012 ); break; end
                    if not num:isWithin( dev2.Clarity2012, steadyState.Clarity2012, 1 ) then app:logV( "Clarity changed from ^1 to ^2", steadyState.Clarity2012, dev2.Clarity2012 ); break; end
                    app:logV( "Steady state has been reached after ^1 checks", count )
                    return dev2
                until true
                Debug.pause( "Steady state not reached on first retry." )
            end
            steadyState = dev2
        until true
        count = count + 1
        if count > maxCount then
            -- probably should be verbose, but it generally indicates a problem I want to track down whether user has V-logging enabled, so...
            app:log( "Basic settings did not settle as expected - current values:" )
            app:log( "Exposure: ^1, Contrast: ^2, Highlights: ^3, Shadows: ^4, Whites: ^5, Blacks: ^6, Clarity: ^7",
                dev2.Exposure2012, dev2.Contrast2012, dev2.Highlights2012, dev2.Shadows2012, dev2.Whites2012, dev2.Blacks2012, dev2.Clarity2012 )
            if expSettings then
                app:log( "Expected values: Exposure: ^1, Contrast: ^2, Highlights: ^3, Shadows: ^4, Whites: ^5, Blacks: ^6, Clarity: ^7",
                    expSettings.Exposure2012 or "n/a", expSettings.Contrast2012 or "n/a", expSettings.Highlights2012 or "n/a", expSettings.Shadows2012 or "n/a", expSettings.Whites2012 or "n/a", expSettings.Blacks2012 or "n/a", expSettings.Clarity2012 or "n/a" )
            end
            return dev2, "PV2012 settings have not settled (after a fairly long wait)."
        end
        LrTasks.sleep( .1 ) -- give dev-settings another moment.
        dev2 = self:getDevelopSettings( photo )
    until shutdown
    assert( shutdown, "not shutdown" )
    return dev2, "shutdown"
end



--- Assures legacy settings are settled, generally after auto-tone applied, presumably in calling context.
--
--  @usage Could also be called to assure photo has settled after changing process version.
--
function DevelopSettings:assureLegacyBasicSettings( photo, dev )
    local count = 1
    local dev2 = dev or self:getDevelopSettings( photo )
    if str:getFirstChar( dev2.ProcessVersion ) ~= '5' then
        local rawValue, fmtValue = self:constrainSetting( 'ProcessVersion', dev2.ProcessVersion )
        fmtValue = fmtValue or rawValue
        return dev2, str:fmtx( "Legacy basic settings do not apply to photos whose process version is '^1'.", fmtValue )
    end
    repeat
        repeat
            if dev2.Exposure == nil or dev2.Exposure < -4 or dev2.Exposure > 4 then break end
            if dev2.HighlightRecovery == nil or dev2.HighlightRecovery < 0 or dev2.HighlightRecovery > 100 then break end
            if dev2.FillLight == nil or dev2.FillLight < 0 or dev2.FillLight > 100 then break end
            if dev2.Shadows == nil or dev2.Shadows < 0 or dev2.Shadows > 100 then break end -- blacks.
            if dev2.Brightness == nil or dev2.Brightness < -150 or dev2.Brightness > 150 then break end
            if dev2.Contrast == nil or dev2.Contrast < -50 or dev2.Contrast > 100 then break end
            if dev2.Clarity == nil or dev2.Clarity < -100 or dev2.Clarity > 100 then break end
            -- Note: not checking for legacy tone-curve... - must be done independently if need be.
            app:logv( "Legacy basic settings are all settled (after ^1 checks)", count )
            return dev2
        until true
        count = count + 1
        if count > 60 then -- 6 seconds.
            return dev2, "Legacy settings have not settled (after a good 6 second wait)."
        end
        LrTasks.sleep( .1 ) -- give dev settings another moment.
        dev2 = self:getDevelopSettings( photo )
    until shutdown
    assert( shutdown, "not shutdown" )
    return dev2, "shutdown"
end



--- Assure stabilized basic settings, of any process version.
--
function DevelopSettings:assureBasicSettings( photo, dev )
    local oldSettings = dev or self:getDevelopSettings( photo )
    local errm
    local sleptEnough
    local function assure()
        local pv = oldSettings.ProcessVersion
        if pv ~= nil then
            if str:getFirstChar( pv ) == '6' then -- PV2012
                oldSettings, errm = developSettings:assurePv2012BasicSettings( photo, oldSettings )
                --Debug.pause( oldSettings, errm )
                -- 6 seconds of sleep built-in.
                return
            elseif str:getFirstChar( pv ) == '5' then -- legacy
                oldSettings, errm = developSettings:assureLegacyBasicSettings( photo, oldSettings )
                --Debug.pause( oldSettings, errm )
                -- 6 seconds of sleep built-in.
                return
            end
        end
        oldSettings = nil
        errm = str:fmtx( "Unidentified process version: '^1'", str:to( pv ) )
        --Debug.pause( errm )
        if not sleptEnough then
            app:sleep( 6 ) -- sleep in case process version needs to find it's way in...
            sleptEnough = true
        end
    end
    assure() -- sleeping plenty to wait for potential settling.
    if errm == nil then
        assert( oldSettings, "no old settings" )
        return oldSettings
    end
    -- Debug.pause( errm )
    oldSettings = self:getDevelopSettings( photo ) -- try again with fresh settings.
    assure() -- no excessive sleeping if process version not legal.
    return oldSettings, errm
end



--- Apply develop setting adjustments, absolutely, respecting pre-requisites, and optionally: constraints.
--
--  @usage Must *NOT* be pre-wrapped for catalog access.
--  @usage internally wrapped for error handling, so returns status, message instead of throwing errors, if possible.
--  @usage operates synchronously, so must be called from async task.
--
--  @param params containing:
--      <br>adjustmentRecords (array) elements:
--      <br>    photo
--      <br>    settings
--      <br>    title
--      <br>undoTitle (string, default is computed).
--      <br>caption (string, optional) scope caption.
--      <br>preConstrained (boolean, default=false) if true, constraints will not be re-evaluated.
--      <br>metadataCache (lr-metadata cache, default=nil) if passed, will be used for efficient metadata access.
--      <br>call (Call, default=nil) if passed, caption & progress will be updated.
--
--  @return status (boolean) t or f.
--  @return message (string) nil or error.
--
function DevelopSettings:applyAdjustments( params )

    -- Note: using gate instead of guard.
    return app:pcall{ name="Develop Settings - Apply Adjustments", guard=App.guardNot, main=function( call )

        local s, m = self.applyAdjGate:enter() -- working nicely for one-at-a-time access to catalog for develop settings adjustment.
        if not s then error( m ) end -- error -> status/message.
        
        local adjRecs = params.adjustmentRecords or error( "no adjustment records" )
        local preConstrained = params.preConstrained -- or false.
        local undoTitle = params.undoTitle -- or nil.
        local mainCaption = params.caption or "Applying develop adjustments"
        local service = params.call -- or scope won't be updated (not recommended).
        local cache = params.metadataCache -- or does without.

        if not str:is( undoTitle ) then
            if #adjRecs == 1 then -- one photo.
                if str:is( adjRecs[1].title ) then
                    undoTitle = adjRecs[1].title
                else -- reminder, one adj-rec per photo - may have multiple adjustements.
                    undoTitle = "adjustments to 1 photo" -- if more descriptive title desired, assign it to adj-rec in calling context.
                end
            else
                undoTitle = str:fmtx( "adjustments to ^1 photos", #adjRecs )
            end
        -- else calling context set desired undo title (e.g. preset-name).
        end
    
        assert( not catalog.hasWriteAccess, "must not be wrapped for catalog access" )
        local function cap( txt, ... )
            if not service then return end
            service:setCaption( txt, ... )
            LrTasks.yield()
        end
        local function prog( a, b )
            if not service then return end
            service:setPortionComplete( a, b )
        end
        local function isQuit()
            if not service then return shutdown end
            return service:isQuit()
        end
        -- eval/apply prerequisite settings, if any
        local yc = 0
        local prereqApplied = 0
        local prereqFuncs = {}
        -- ideally, auto-tone settings should be teased out and applied separately, with settling validation.
        -- otherwise, applying auto-toning in conjunction with other basic adjustments (or non-basic?) will fail. ###2
        local function applyPrereq()
            cap( "Evaluating pre-requisites" )
            for i, adjRec in ipairs( adjRecs ) do
                local photo = adjRec.photo
                prog( i - 1, #adjRecs )
                for id, value in pairs( adjRec.settings ) do
                    local lookup = self.settingLookup[id]
                    if lookup then
                        local prereq = lookup.prereq
                        if prereq ~= nil then
                            local dev = self:getDevelopSettings( photo )
                            if dev[prereq.name] == prereq.value then
                                -- good to go
                                app:logVerbose( "Pre-requisite is satisfied for ^1: ^2=^3", id, prereq.name, prereq.value )
                            else
                                local set = {}
                                set[prereq.name] = prereq.value
                                local name = str:fmt( "Prerequisite: ^1=^2", prereq.name, prereq.value )
                                local preset = LrApplication.addDevelopPresetForPlugin( _PLUGIN, name, set ) -- let it auto-append a uniqueness id if need be.
                                if preset then
                                    --Debug.lognpp( set )
                                    prereqFuncs[#prereqFuncs + 1] = function()
                                        photo:applyDevelopPreset( preset, _PLUGIN )
                                        --prereqApplied = prereqApplied + 1
                                        --app:logv( "Applied pre-requisite - ^1", name )
                                    end
                                else
                                    app:error( "No preset" )
                                end
                            end
                        -- else no pre-req                        
                        end
                    else
                        -- app:error( "invalid develop setting ID: ^1", id )
                        dbgf( "unregistered setting: ^1", id )
                    end
                end
                if isQuit() then
                    return
                else
                    yc = app:yield( yc )
                end 
            end
            prog( 1 )
            if #prereqFuncs > 0 then
                cap( "Applying pre-requisites" )
                local s, m = cat:update( 20, "Applying Develop Pre-requisites", function( context, phase )
                    for i, func in ipairs( prereqFuncs ) do
                        prog( i - 1, #prereqFuncs )
                        func()
                        if isQuit() then
                            return
                        else
                            yc = app:yield( yc )
                        end
                    end
                end )
                prog( 1 )
                if s then
                    prereqApplied = #prereqFuncs
                    app:log( "Pre-requisites applied." )
                else
                    error( m )
                end
            else
                app:logv( "No pre-requisites to apply." )
            end
        end
        local function applyAdj()
            -- apply adjustments
            cap( mainCaption )
            for i, adjRec in ipairs( adjRecs ) do
                repeat
                    local photo = adjRec.photo
                    local isVideo = lrMeta:getRaw( photo, 'fileFormat', cache ) == 'VIDEO' -- accept uncached.
                    if isVideo then
                        app:logv( "Develop settings do not apply to videos, ignoring: ^1", lrMeta:getRaw( photo, 'path', cache ) )
                        break
                    end
                    prog( i - 1, #adjRecs )
                    local settings
                    if preConstrained then
                        settings = adjRec.settings or app:callingError( "No settings in adjustment record" )
                    else
                        settings = self:constrainSettings( adjRec.settings ) or app:callingError( "No settings after constraining those in adjustment record" )
                    end
                    --Debug.lognpp( settings )
                    local preset = LrApplication.addDevelopPresetForPlugin( _PLUGIN, adjRec.title, settings )
                    if preset then
                        app:logVerbose( "\"Added\" new or changed develop preset for plugin: ^1", adjRec.title )
                    else
                        error( "No preset" )
                    end
                    photo:applyDevelopPreset( preset, _PLUGIN )
                    if isQuit() then
                       return
                    else
                        yc = app:yield( yc )
                    end 
                until true
            end            
            prog( 1 )
        end
        -- @1/Mar/2013 0:14 - I don't remember why I commented out the cat-update wrapper - probably because Lr needs to get to work on those pre-requisites in parallel.
        --local s, m = cat:update( 20, "Evaluating/Applying Pre-requisite Settings", function( context, phase )
            -- Note: could do 100 or 1000 at a time, like cookmarks, but really: are people going to be adjusting multi-thousands at once? (maybe) ###2
            applyPrereq()
        --end )
        --if s then
            if prereqApplied > 0 then
                cap( "Waiting for pre-requisites to settle..." )
                local settlingTimePerOp = app:getPref( 'settlingTimePerOp' ) or 3 -- *very* conservative, but better safe than sorry: recommend - assuring pre-reqs met using Lr or upon import instead.
                local time = math.min( prereqApplied * settlingTimePerOp, 30 ) -- sleep x seconds for each pre-requisite function executed, up to a total potential max of 30 seconds.
                    -- ###2 (there's probably a better way).
                app:logv( "Waiting ^1 seconds for pre-requisites to settle.", time )
                app:sleep( time )
            else
                app:logv( "No pre-requisites applied." )
            end
        --else
            --app:error( "Prerequiste adjustment failed, error message: ^1", m )
        --end
        local s, m = cat:update( 20, undoTitle, function( context, phase )
            -- Note: could do 100 or 1000 at a time, like cookmarks, but really: are people going to be adjusting multi-thousands at once? (maybe) ###2
            applyAdj()
        end )
        if not s then
            error( m )
        end
    end, finale=function( call )
        self.applyAdjGate:exit()
    end }
end



--[[ never used:
function DevelopSettings:isPv2012Code( code )
    if code == DevelopSettings.pvCode2012 then
        return true
    elseif code == DevelopSettings.pvCodeLegacy then
        return false
    else
        app:callingError( "Invalid pv code: ^1", code )
    end
end
function DevelopSettings:isLegacyCode( code )
    if code == DevelopSettings.pvCodeLegacy then
        return true
    elseif code == DevelopSettings.pvCode2012 then
        return false
    else
        app:callingError( "Invalid pv code: ^1", code )
    end
end
--]]



--- Determine if process version (pass pv string or whole dev-settings table) is PV2012.
--
function DevelopSettings:isPv2012( pv )
    if pv == nil then return false end -- presumably video.
    if type( pv ) == 'table' then
        pv = pv.ProcessVersion
        if pv == nil then return false end -- ditto.
    end
    -- Note: it seems process version 6.6 is not necessarily string (may be number).
    if type( pv ) == 'number' then
        pv = tostring( pv )
    -- else let lookup handle it (presumably string).
    end
    local lookup = pvLookup[pv]
    if lookup then
        if lookup.pvCode == DevelopSettings.pvCode2012 then
            return true, lookup
        else
            return false, lookup
        end
    else
        app:callingError( "Invalid pv: ^1", pv )
    end
end



--- Determine if process version (pass pv string or whole dev-settings table) is a legacy process version.
--
function DevelopSettings:isLegacy( pv )
    if pv == nil then return false end -- presumably video.
    if type( pv ) == 'table' then -- presumably develop settings themselves.
        pv = pv.ProcessVersion
        if pv == nil then return false end -- ditto.
    end
    -- Note: it seems process version 6.6 is not necessarily string (may be number).
    if type( pv ) == 'number' then
        pv = tostring( pv )
    -- else let lookup handle it (presumably string).
    end
    local lookup = pvLookup[pv]
    if lookup then
        if lookup.pvCode == DevelopSettings.pvCodeLegacy then
            return true, lookup
        else
            return false, lookup
        end
    else
        app:callingError( "Invalid pv: ^1", pv )
    end
end



--- Get develop settings for photo or video, when available.
--  (not available when video has trim-end=nil).
function DevelopSettings:getDevelopSettings( photo, autoToneFlag )
    local sts, ds = LrTasks.pcall( photo.getDevelopSettings, photo )
    if sts then
        return ds
    else
        return {}
    end
end



--- Get Adobe default settings, for reset purposes..
--  @param  fmt     type: 'raw', 'rgb'.
--  @param  pv      process version: pv from develop settings, or all develop settings - not pv-code.
--  @return develop settings - adjustment table (preset-compatible format).
function DevelopSettings:getAdobeDefaultSettings( fmt, pv )
    local adj = {}
    -- pv hard-coded a.t.m.
    local raw
    if fmt == 'raw' then
        raw = true
        adj.WhiteBalance = "As Shot" -- no change to temperature and tint.
        app:logW( "@28/Sep/2013 12:07 - raw reset/default-settings not tested." )
        Debug.pause( "*** raw reset/default-settings not tested" )
    elseif fmt == 'rgb' then
        -- hardly matters what white-balance is set at, when incremental values are zero, i.e. as-shot is essentially the same as zero.
        adj.IncrementalTemperature = 0
        adj.IncrementalTint = 0
    else
        app:callingError( "bad fmt: ^1", fmt )
    end
    
    local pv2012
    if pv == nil then
        pv2012 = true
    elseif self:isPv2012( pv ) then
        pv2012 = true
    elseif self:isLegacy( pv ) then
        pv2012 = false
        app:logW( "@28/Sep/2013 12:07 - legacy reset/default-settings not tested." )
        Debug.pause( "*** legacy reset/default-settings not tested" )
    else
        app:callingError( "Bad pv: ^1", pv )
    end
    
    -- Basics (less WB)
    if pv2012 then
        adj.Exposure2012 = 0
        adj.Contrast2012 = 0
        adj.Highlights2012 = 0
        adj.Shadows2012 = 0
        adj.Whites2012 = 0
        adj.Blacks2012 = 0
        adj.Clarity2012 = 0
    else
        adj.Exposure = 0
        adj.Brightness = 50
        adj.Contrast = 25
        adj.FillLight = 0
        adj.HighlightRecovery = 0
        adj.Blacks = 5
    end
    adj.Vibrance = 0
    adj.Saturation = 0
    
    -- Parametric curve.
    adj.ParametricShadowSplit = 25
    adj.ParametricMidtoneSplit = 50
    adj.ParametricHighlightSplit = 75
    adj.ParametricShadows = 0
    adj.ParametricDarks = 0
    adj.ParametricLights = 0
    adj.ParametricHighlights = 0
    
    -- Point curves.
    if pv2012 then
        adj.ToneCurvePV2012 = { 0, 0, 255, 255 }
        adj.ToneCurvePV2012Red = { 0, 0, 255, 255 }
        adj.ToneCurvePV2012Green = { 0, 0, 255, 255 }
        adj.ToneCurvePV2012Blue = { 0, 0, 255, 255 }
    else
        adj.ToneCurve = { 0, 0, 255, 255 }
    end
    
    -- HSL
    adj.HueAdjustmentRed = 0
    adj.HueAdjustmentOrange = 0
    adj.HueAdjustmentYellow = 0
    adj.HueAdjustmentGreen = 0
    adj.HueAdjustmentAqua = 0
    adj.HueAdjustmentBlue = 0
    adj.HueAdjustmentPurple = 0
    adj.HueAdjustmentMagenta = 0
    adj.SaturationAdjustmentRed = 0
    adj.SaturationAdjustmentOrange = 0
    adj.SaturationAdjustmentYellow = 0
    adj.SaturationAdjustmentGreen = 0
    adj.SaturationAdjustmentAqua = 0
    adj.SaturationAdjustmentBlue = 0
    adj.SaturationAdjustmentPurple = 0
    adj.SaturationAdjustmentMagenta = 0
    adj.LuminanceAdjustmentRed = 0
    adj.LuminanceAdjustmentOrange = 0
    adj.LuminanceAdjustmentYellow = 0
    adj.LuminanceAdjustmentGreen = 0
    adj.LuminanceAdjustmentAqua = 0
    adj.LuminanceAdjustmentBlue = 0
    adj.LuminanceAdjustmentPurple = 0
    adj.LuminanceAdjustmentMagenta = 0
    
    -- B&W
    adj.GrayMixerRed = 0
    adj.GrayMixerOrange = 0
    adj.GrayMixerYellow = 0
    adj.GrayMixerGreen = 0
    adj.GrayMixerAqua = 0
    adj.GrayMixerBlue = 0
    adj.GrayMixerPurple = 0
    adj.GrayMixerMagenta = 0
    
    -- Splits
    adj.SplitToningHighlightHue = 0
    adj.SplitToningHighlightSaturation = 0
    adj.SplitToningBalance = 0
    adj.SplitToningShadowHue = 0
    adj.SplitToningShadowSaturation = 0
    
    -- Detail
    if raw then
        adj.Sharpness = 25
        adj.ColorNoiseReduction = 25
    else
        adj.Sharpness = 0
        adj.ColorNoiseReduction = 0
    end
    adj.SharpenRadius = 1
    adj.SharpenDetail = 25
    adj.SharpenEdgeMasking = 0
    adj.LuminanceSmoothing = 0
    adj.LuminanceNoiseReductionDetail = 50
    adj.LuminanceNoiseReductionContrast = 0
    adj.ColorNoiseReductionDetail = 50
    adj.ColorNoiseReductionSmoothness = 50
    
    -- LC
    adj.LensProfileEnable = 0
    adj.LensProfileSetup = "Default"
    -- these may not be 'zactly what Lr would do upon reset, but hopefully won't blow the deal, since profile corrections will be disabled. ###4
    -- I wouldn't have any idea what else to set them to, so...
    -- reminder: Make & Model are derivatives that are neither readable nor settable via SDK, @28/Sep/2013 12:19.
    -- adj.LensProfileName = ""
    -- adj.LensProfileFilename = ""
    adj.LensProfileDistortionScale = 0
    adj.LensProfileVignettingScale = 0
    adj.AutoLateralCA = 0
    adj.DefringePurpleAmount = 0
    adj.DefringePurpleHueLo = 30
    adj.DefringePurpleHueHi = 70
    adj.DefringeGreenAmount = 0
    adj.DefringeGreenHueLo = 40
    adj.DefringeGreenHueHi = 60
    adj.LensManualDistortionAmount = 0
    adj.PerspectiveVertical = 0
    adj.PerspectiveHorizontal = 0
    adj.PerspectiveRotate = 0
    adj.PerspectiveScale = 0
    adj.CropConstrainToWarp = 0
    adj.VignetteMidpoint = 50
    adj.VignetteAmount = 0
    
    -- Effects
    adj.PostCropVignetteStyle = 1 -- 1 is highlight-priority; 2 is color priority; 3 is paint-overlay (zero will also impose highlight priority, as opposed to being ignored).
    adj.PostCropVignetteAmount = 0
    adj.PostCropVignetteMidpoint = 50
    adj.PostCropVignetteRoundness = 0
    adj.PostCropVignetteFeather = 50
    adj.PostCropVignetteHighlightContrast = 0
    adj.GrainAmount = 0
    adj.GrainSize = 25
    adj.GrainFrequency = 50

    -- Camera Calibration
    if pv2012 then
        adj.ProcessVersion = "6.7"
    else
        adj.ProcessVersion = "5.7" -- pv2010.
    end
    if raw then
        adj.CameraProfile = "Adobe Standard"
    else
        adj.CameraProfile = "Embedded"
    end
    adj.ShadowTint = 0
    adj.RedHue = 0
    adj.RedSaturation = 0
    adj.GreenHue = 0
    adj.GreenSaturation = 0
    adj.BlueHue = 0
    adj.BlueSaturation = 0
    
    -- Ena/Dis. - not doing.
    
    adj.RetouchInfo = {}
    adj.RetouchAreas = {}
    adj.RedEyeInfo = {}
    adj.GradientBasedCorrections = {}
    adj.CircularGradientBasedCorrections = {}
    adj.PaintBasedCorrections = {}

    -- reminder: if settings aren't recognized, they're ignored.
    
    return adj
end



--[[ Determine if photo has significant adjustments or not.
-- on hold..
function DevelopSettings:isAdjusted( photo, settings, mode, cache, call )
    if photo.photo then -- named parameters
        local params = photo
        settings = params.settings
        mode = params.mode or 'minimal'
        cache = params.cache
        call = params.call
        photo = params.photo -- must be last.
        
    -- else positional parameters
    end
    settings = settings or photo:getDevelopSettings()
    local format = lrMeta:getRaw( photo, 'fileFormat', cache )
    local fmt
    if format == 'RAW' or format == 'DNG' then -- ###3 dng treated as raw whether it is or not.
        fmt = 'raw'
    else
        fmt = 'rgb'
    end
    if mode == 'minimal' then
    elseif mode == 'complete"
    local defaults = self:getAdobeDefaultSettings( fmt, settings.ProcessVersion )
    for k, v in pairs( defaults ) do
        if type( settings ) ~= 'table' then
            if defaults( 
    end
end
--]]



return DevelopSettings
