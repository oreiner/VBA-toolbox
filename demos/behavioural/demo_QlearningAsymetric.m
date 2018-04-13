function [posterior, out] = demo_QlearningAsymetric (data)
% // VBA toolbox //////////////////////////////////////////////////////////
%
% [posterior, out] = demo_QlearningAsymetric ([data])
% Demo of Q-learning with asymetric learning rates for positive and
% negative predictions errors.
%
% This demo implements the experiment described in Frank et al. 2004, Science
%
% If no inputs are given, the demo will generate artificial data for both
% the learning and the test blocs and invert all data at once.
%
% IN:
%   - [data]: 
%       - cues: 2 x T vector indicating the identity of the two cues
%            presented at each trial
%       - choices: 1 X T binary vector indicating if the subject chose the 
%            first (choice = 0) or the second (choice = 1) cue as encoded 
%            in data.cues
%       - feedbacks: 1 X T vector describing the outcome of the choice. If
%            a trial has no feedback (e.g. in test bloc), set value to NaN. 
%
% OUT:
%   - posterior, out: results of the inversion 
%
% /////////////////////////////////////////////////////////////////////////

Nbandits = 3;

% check inputs
% =========================================================================

switch nargin
    case 0
        fprintf ('No inputs provided, generating simulated behavior...\n\n');
        data = simulateQlearningAsym ();
    case 2
        fprintf ('Performing inversion of provided behaviour...\n\n');
    otherwise
        error ('*** Wrong number of arguments.')
end
        
% reformat data
% =========================================================================
% observations
y = data.choices;

% inputs
u = [ nan, data.choices(1 : end - 1) ;  % previous choice
      nan, data.feedbacks(1 : end - 1) ; % previous feedback
      nan(2,1), data.cues(:, 1 : end - 1) ; % previous pair
      data.cues ]; % identity of the presented cues

% specify model
% =========================================================================
f_fname = @f_QlearningAsym; % evolution function (Q-learning)
g_fname = @g_QLearning; % observation function (softmax mapping)

% provide dimensions
dim = struct( ...
    'n', 2 * Nbandits, ... number of hidden states (2*N Q-values)
    'n_theta', 2, ... number of evolution parameters (1: learning rate, 2: valence effect)
    'n_phi', 1 ... number of observation parameters (1: temperature)
   );
    
% options for the simulation
% -------------------------------------------------------------------------
% use the default priors except for the initial state
options.priors.muX0 = 0.5 * ones (dim.n, 1);
options.priors.SigmaX0 = 0.01 * eye (dim.n);

%options.priors.SigmaTheta = diag([0.1 0.1]);

options.priors.muPhi = log(2.5);
options.priors.SigmaPhi = 0.1;

% options for the simulation
% -------------------------------------------------------------------------
% number of trials
n_t = numel(data.choices); 
% fitting binary data
options.binomial = 1;
options.verbose = false;

% invert model
% =========================================================================
[posterior, out] = VBA_NLStateSpaceModel(y, u, f_fname, g_fname, dim, options);

% display estimated parameters:
% -------------------------------------------------------------------------
fprintf('=============================================================\n');
fprintf('\nEstimated parameters: \n');
fprintf('  - avg. learning rate: %3.2f\n', sigm(posterior.muTheta(1)));
fprintf('  - learning rate asym: %3.2f\n', posterior.muTheta(2));
fprintf('  - inverse temp.: %3.2f\n\n', exp(posterior.muPhi));
fprintf('=============================================================\n');

% invert model
% =========================================================================
if exist('simulation','var') % used simulated data from demo_QlearningSimulation
    displayResults( ...
        posterior, ...
        out, ...
        choices, ...
        simulation.state, ...
        simulation.initial, ...
        simulation.evolution, ...
        simulation.observation, ...
        Inf, Inf ...
     );
end

end

function data = simulateQlearningAsym ()

% training bloc
% -------------------------------------------------------------------------

nTrials = 120; 

% define pairs
cues = [repmat([1; 2], 1, nTrials) ... % A B
        repmat([3; 4], 1, nTrials) ... % C D
        repmat([5; 6], 1, nTrials) ];  % E F
    
% define contingencies for each pair
contingencies = [zeros(1, 0.8 * nTrials), ones(1, 0.2 * nTrials) ...
                 zeros(1, 0.7 * nTrials), ones(1, 0.3 * nTrials) ...
                 zeros(1, 0.6 * nTrials), ones(1, 0.4 * nTrials) ];

% shuffle
p = randperm (numel (contingencies))   ;
cues = cues(:, p);
contingencies = contingencies(p);

% testing bloc
% -------------------------------------------------------------------------

nTest = 1;

test = [1 1 1 1 2 2 2 2;
        3 4 5 6 3 4 5 6];

test = repmat(test,1,nTest);

cues = [cues test];
contingencies = [contingencies nan(1, size(test,2))];
   
% create feedback structure for the simulation with VBA    
% -------------------------------------------------------------------------
% feedback function. Return 1 if action follow contingencies, nan if no feedback.
h_feedback = @(yt,t,in) (yt == contingencies(t)) * sign(1+contingencies(t));
% feedback structure for the VBA
fb = struct( ...
    'h_fname', h_feedback, ... % feedback function  
    'indy', 1, ... % where to store simulated choice
    'indfb', 2, ... % where to store simulated feedback
    'inH', struct() ...
   );

% Simulate choices for the given feedback rule
% =========================================================================

% define parameteters of the simulated agent    
% -------------------------------------------------------------------------
% learning rate
theta = [0.6 0.3]; % learning, asymmetry
% inverse temperature 
phi = log(2.5); % will be exp transformed
% initial state
x0 = 0.5 * ones(6,1);

% options for the simulation
% -------------------------------------------------------------------------
% number of trials
n_t = numel(contingencies); 
% fitting binary data
options.binomial = 1;
options.verbose = false;

% simulate choices
% -------------------------------------------------------------------------

u = [nan(2, n_t); cues];

[y,x,x0,eta,e,u] = simulateNLSS( ...
    n_t, ... number of trials
    @f_QlearningAsym, ... evolution function
    @g_QLearning, ... observation function
    theta, ... evolution parameters (learning rate)
    phi, ... observation parameters,
    u, ... dummy inputs
    Inf, Inf, ... deterministic evolution and observation
    options, ... options
    x0, ... initial state
    fb ... feedback rule
   );


% Return simulated choices, feedbacks, and parameters used for the
% simulation
% =========================================================================
data.choices = y;
data.feedbacks = [u(2,2:end) nan];
data.cues = cues;

% Display stat of simulated behaviour
% =========================================================================
testT = numel(y) - size(test, 2) : numel(y);
testY = y(testT);
testU = u(:,testT);
chooseA = mean(testY(testU(3,:) == 1) == 0);
avoidB = mean(testY(testU(3,:) == 2) == 1);

fprintf('=============================================================\n');
fprintf('Simulated choice with asymetric learning: %03.2f\n',theta(2));

fprintf('  - Choose A: %03.2g%%\n',chooseA);
fprintf('  - Avoid  B: %03.2g%%\n',avoidB);
fprintf('=============================================================\n');

end
  

