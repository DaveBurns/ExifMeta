--[[----------------------------------------------------------------------------
12345678901234567890123456789012345678901234567890123456789012345678901234567890

DelayedProgressScope

Copyright 2010, John R. Ellis -- You may use this script for any purpose, as
long as you include this notice in any versions derived in whole or part from
this file.

--------------------------------------------------------------------------
MODIFIED BY ROB COLE (RDC) TO ADAPT TO THE ELARE PLUGIN FRAMEWORK.
(changes indicated by RDC below)
--------------------------------------------------------------------------

A DelayedProgressScope is logically a subclass of LrProgressScope that only
displays after a specified amount of time has elapsed.  The client always
creates the scope, but the scope will display only if there is a lot of "work"
to be done, e.g. after a given amount of time has expired.  This is appropriate
for situations where the amount of work to be done can vary from very small to
very large, and only in the latter situations should a scope be displayed.

A DelayedProgressScope supports all the methods of LrProgressScope.
------------------------------------------------------------------------------]]

local DelayedProgressScope = Object:newClass{ className = 'DelayedProgressScope', register = false } -- RDC

--[[require 'strict'

local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrProgressScope = import 'LrProgressScope'

local Debug = require 'Debug'

DelayedProgressScope.__index = DelayedProgressScope--]]

    -- Forward references
local createScope

--[[----------------------------------------------------------------------------
void new (params)

Creates a new DelayedProgressScope. Params:

- modal (boolean, default true): true if this is a modal scope.

- delaySecs (number, default 1): the number of seconds allowed to elapse before an
actual scope is displayed.

- updateSecs (number, default 0.25): the number of seconds between actual
updates to the display of the scope.  This allows thousands or hundreds of
thousands of call to setCaption() or setPortionComplete() per second without
paying much overhead.

The following parameters have the same meaning as in
LrDialogs.showModalProgressScope() and LrProgressScope():

cannotCancel, functionContext, title, caption, parent, parentEndRange
------------------------------------------------------------------------------]]



--  RDC
--- Constructor for extending class.
--  
function DelayedProgressScope:newClass( t )
    local o = Object.newClass( self, t )
    return o
end



--  RDC
--- Constructor for new instances.
--
--  @param      t       Initial table, with all the same members as regular lr-progress-scope, plus (all are optional):
--                      <ul>
--                          <li>functionContext (lr-function-context, default nil): if not set in constructor, must be manually attached afterward.
--                          <li>modal (boolean, default true): set true to use modal dialog box instead of the upper left corner.
--                          <li>indeterminate (boolean, default true): calling set-portion-complete converts an indeterminate scope to a determinate one.
--                          <li>cannotCancel (boolean, default false): set true to make it un-cancelable.
--                          <li>delaySecs (number, default 1): the number of seconds allowed to elapse before an actual scope is displayed.
--                          <li>updateSecs updateSecs (number, default 0.25): the number of seconds between actual updates to the display of the scope.  This allows thousands or hundreds of thousands of call to setCaption() or setPortionComplete() per second without paying much overhead.
--                      </ul>
--
--  @usage      Can be used anywhere a LrProgressScope object can be used, except:
--              <br>supports determinate progress scopes only - i.e. you have to set portion-complete or the actual scope will never by created.
--
function DelayedProgressScope:new( t )
    local o = Object.new( self, t )
    if o.modal == nil then
        -- o.modal = true
        o.modal = false -- changed 22/Oct/2012 14:54, since I primarily use non-modal scopes - hope this is OK (I did a brief check first of course).
    end
    if o.indeterminate == nil then
        o.indeterminate = true
    end
    o.cancelable = not o.cannotCancel -- default for cancelable is true, however app must still check for cancelation or it does no good.
    -- title is mandatory for parent scopes, but not child scopes.
    -- caption is optional
    -- parent is optional
    -- parent-end-range is optional
    -- functionContext - optional but recommended...
    o.delaySecs = o.delaySecs or 1
    o.updateSecs = o.updateSecs or 0.25
    o.start = LrDate.currentTime()
    if o.delaySecs == 0 then
        createScope(o)
    elseif o.indeterminate then -- clause added 22/Oct/2012 14:38, since I got tired of un-goosed scopes never appearing.
        LrTasks.startAsyncTask( function()
            app:sleep( o.delaySecs, .1, function()
                if o.canceledState or o.doneState then
                    return true -- end-of-sleep when scope is canceled.
                end
            end )
            if not shutdown and not o.canceledState and not o.doneState and not o.scope then
                createScope( o )
                if o.scope and o.caption then
                    o.scope:setCaption( o.caption )
                end
            end
        end )
    end
    return o
end


--  RDC
--- Call to indicate operation is progressing, yet amount til completion unknown.
--
--  @param      yield (boolean, default: false) true => yield every update interval.
--              <br>Leave false if calling context yields naturally, but yields are necessary for scope to be displayed.
--
--  @usage      auto-converts determinate progress scope to indeterminate one.
--  @usage      must be called from task or it'll never get displayed.
--
function DelayedProgressScope:setIndeterminateProgress( yield )
    self.indeterminate = true
    local t = LrDate.currentTime ()
    if self.scope then 
        if t - self.start >= self.updateSecs then 
            self.scope:setIndeterminate()
            self.start = t
            if yield then
                LrTasks.yield() -- ok - down-throttling built in.
            end
        end
    else
        if t - self.start >= self.delaySecs then 
            createScope (self)
            self.start = t
        end
    end
end

    
    
function DelayedProgressScope:attachToFunctionContext (context)
    if self.scope then
        self.scope:attachToFunctionContext (context)
    else
        self.functionContext = context
        end
    end

function DelayedProgressScope:cancel()
    if self.scope then
        self.scope:cancel ()
    else
        self.canceledState = true
        end
    end

function DelayedProgressScope:isCanceled()
    if self.scope then
        return self.scope:isCanceled ()
    else
        return self.canceledState
        end
    end

function DelayedProgressScope:done()
    if self.scope then
        self.scope:done ()
    else
        self.doneState = true
        end
    end
    
function DelayedProgressScope:isDone()
    if self.scope then
        return self.scope:isDone ()
    else
        return self.doneState
        end
    end
    
function DelayedProgressScope:isCancelable()
    if self.scope then
        return self.scope:isCancelable ()
    else 
        return self.cancelable
        end
    end

function DelayedProgressScope:setCancelable (cancelable)
    if self.scope then
        self.scope:setCancelable (cancelable)
    else
        self.cancelable = cancelable
        end
    end

function DelayedProgressScope:isIndeterminate()
    if self.scope then
        return self.scope:isIndeterminate ()
    else
        return self.indeterminate
        end
    end

function DelayedProgressScope:setIndeterminate()
    if self.scope then
        self.scope:setIndeterminate ()
    else
        self.indeterminate = true
        end
    end

function DelayedProgressScope:getPortionComplete ()   
    if self.scope then
        return self.scope:getPortionComplete ()
    else
        return self.amountDone
        end
    end

function DelayedProgressScope:setCaption (caption)
    local t = LrDate.currentTime ()
    if self.scope then 
        if t - self.start >= self.updateSecs then 
            self.scope:setCaption (caption)
            self.start = t
            end
    else
        self.caption = caption
        if t - self.start >= self.delaySecs then 
            createScope (self)
            self.start = t
            end
        end
    end

function DelayedProgressScope:setPortionComplete (amountDone, totalAmount)
    self.indeterminate = false
    local t = LrDate.currentTime ()
    if self.scope then 
        if t - self.start >= self.updateSecs then 
            self.scope:setPortionComplete (amountDone, totalAmount)
            self.start = t
            end
    else
        self.amountDone = amountDone
        self.totalAmount = totalAmount
        if t - self.start >= self.delaySecs then 
            createScope (self)
            self.start = t
            end
        end
    end
    
function createScope (self)
    if self.canceledState or self.doneState then return end
    if self.modal then 
        self.scope = LrDialogs.showModalProgressDialog {
            title = self.title, caption = self.caption, 
            cannotCancel = not self.cancelable, 
            functionContext = self.functionContext}
    else
        self.scope = LrProgressScope {parent = self.parent, 
            parentRange = self.parentRange, title = self.title, 
            functionContext = self.functionContext}
        end
    if self.cancelable ~= nil then 
        self.scope:setCancelable (self.cancelable)        
        end
    if self.indeterminate then
        self.scope:setIndeterminate ()
        end
    if self.amountDone then 
        self.scope:setPortionComplete (self.amountDone, self.totalAmount)
        end
    end

return DelayedProgressScope