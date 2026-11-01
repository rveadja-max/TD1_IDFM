\NeedsTeXFormat{LaTeX2e}[1995/12/01]
\ProvidesClass{memoirerecherche}[2019/08/28 v0.1 Standard LaTeX document class]
% memoirerecherche is based on the class article
\LoadClass[a4paper, 11pt]{article}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Importing required libraries %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\RequirePackage{graphicx}
\RequirePackage[table]{xcolor}
\RequirePackage{colortbl}
\RequirePackage{hyperref}
\RequirePackage{titlesec}
\RequirePackage{caption} % Coloured captions
\RequirePackage{amsthm}
\RequirePackage{lastpage} %Last page number
% \RequirePackage[figure,table]{totalcount} % Pour avoir les nombres de figures, tables et théoremes
% \RequirePackage{totcount} % Pour compter le nombre de références
%\RequirePackage{thmtools}
\RequirePackage{fontawesome}


%%%%%%%%%%%%%%%%%%%%%%
%% Defining colours %%
%%%%%%%%%%%%%%%%%%%%%%

%% URCA colours
\definecolor{urcalightbrown}{RGB}{172,114, 50}
\definecolor{urcabrown}{RGB}{75,0, 0}
%% Science faculty colours
\definecolor{deepgreenSEN}{RGB}{0,174,66}
\definecolor{greenSEN}{RGB}{0, 121, 52}
\definecolor{lemongreenSEN}{RGB}{118, 188, 33}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Theorem-like environments %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% Custom theorem environments
% \declaretheoremstyle[
%   spaceabove=11pt, spacebelow=11pt,
%   headfont=\color{urcabrown} \normalfont\bfseries\scseries,
%   notefont=\color{urcalightbrown} \normalfont\itshape,
%   bodyfont=\color{black} \normalfont
% ]{urcastyle}


\newtheoremstyle{urcastyle}% name of the style to be used
  {\topsep}% measure of space to leave above the theorem. E.g.: 3pt
  {\topsep}% measure of space to leave below the theorem. E.g.: 3pt
  {\normalfont}% name of font to use in the body of the theorem
  {0pt}% measure of space to indent
  {\color{urcabrown} \bfseries}% name of head font
  {. ---}% punctuation between head and body
  { }% space after theorem head; " " = normal interword space
  {\thmname{#1}\thmnumber{ #2}\textnormal{\thmnote{ (#3)}}}



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Setting up captions options %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\captionsetup[figure]{labelfont={color=urcabrown},textfont=sf, font=small} % Set colour of the captions
\captionsetup[table]{labelfont={color=urcabrown},textfont=sf, font=small} % Set colour of the captions
\captionsetup[algorithm]{labelfont={color=urcabrown},textfont=sf, font=small} % Set colour of the captions


% Custom title commands
\titleformat{\section}
{\color{urcabrown}\normalfont\Large\bfseries}
{\color{urcabrown}\thesection.}{1em}{}
\titlespacing*{\section}
{0pt}{3.3ex}{3.3ex}

\titleformat{\subsection}
{\color{urcabrown}\normalfont\large\bfseries}
{\color{urcabrown}\thesubsection.}{1em}{}
\titlespacing*{\subsection}
{0pt}{3.3ex}{3.3ex}



%%%%%%%%%%%%%%
%% Commands %%
%%%%%%%%%%%%%%

% Defining commands to customize title page
\newcommand{\logouniv}[1]{\def\@logouniv{#1}}
\newcommand{\logoufr}[1]{\def\@logoufr{#1}}
\newcommand{\anac}[1]{\def\@anac{#1}}
\newcommand{\theanac}{\@anac}
\newcommand{\diplome}[1]{\def\@diplome{#1}}
\newcommand{\thediplome}{\@diplome}
\newcommand{\module}[1]{\def\@module{#1}}
\newcommand{\themodule}{\@module}
\newcommand{\enseig}[1]{\def\@enseig{#1}}
\newcommand{\theenseig}{\@enseig}
\newcommand{\evaluation}[1]{\def\@evaluation{#1}}
\newcommand{\theeval}{\@evaluation}
\newcommand{\email}[1]{\def\@email{#1}}
\newcommand{\theauthor}{\@author}
\newcommand{\thetitle}{\@title}
\newcommand{\resume}[1]{\def\@resume{#1}}
\newcommand{\theresume}{\@resume}
\newcommand{\coefficient}[1]{\def\@coefficient{#1}}
\newcommand{\thecoefficient}{\@coefficient}
\newcommand{\keywords}[1]{\def\@keywords{#1}}
\newcommand{\thekeywords}{\@keywords}
\newcommand{\totfig}[1]{\def\@totfig{#1}}
\newcommand{\thetotfig}{\@totfig}
\newcommand{\tottab}[1]{\def\@tottab{#1}}
\newcommand{\thetottab}{\@tottab}
\newcommand{\totref}[1]{\def\@totref{#1}}
\newcommand{\thetotref}{\@totref}
\newcommand{\tottheo}[1]{\def\@tottheo{#1}}
\newcommand{\thetottheo}{\@tottheo}
\newcommand{\gitrepo}[1]{\def\@gitrepo{#1}}
\newcommand{\thegitrepo}{\@gitrepo}
\newcommand{\database}[1]{\def\@database{#1}}
\newcommand{\thedatabase}{\@database}


\logouniv{}
\logoufr{}
\anac{}
\diplome{}
\module{}
\enseig{}
\evaluation{}
\email{}

% Command to set the logo
\newcommand{\thelogo}{}
\newcommand{\logo}[1]{\renewcommand{\thelogo}{#1}}

% Modifying maketitle command
\renewcommand{\maketitle}{
 \thispagestyle{plain}

 \begin{center}
   \includegraphics[height=4.5cm]{\thelogo}
 \end{center}

\vspace{0.3cm}
 {\Large \textbf{\@evaluation}}
 
\vspace{0.3cm}
valant évaluation dans le cadre de :

\begin{tabular}{@{}ll@{}}
 %\hline
  \begin{minipage}[t]{.73\textwidth}
    \noindent
    \scriptsize{\textbf{Diplôme :} \@diplome}  \\
    \scriptsize{\textbf{Année universitaire :} \@anac}\\
    \scriptsize{\textbf{Module d'enseignement :} \@module} \\
    \scriptsize{\textbf{Responsable :} \@enseig} \\
    \scriptsize{\textbf{Comptant pour :} \@coefficient}
% \textbf{Co-encadrants :} \\ % leave it if any co-advisor otherwise comment
% \firstcoadvisor \\ % leave it if any co-advisor otherwise comment
% \secondcoadvisor \\ % leave it if you have more that one co-advisor otherwise comment (if you have more than two co-advisors just copy&paste this line writing \thirdcoadvisor, \fourthcoadvisor, ecc. (REMEMBER to modify also the main.txt)
% \\ % leave it if any co-advisor otherwise comment
  \end{minipage}% This must go next to `\end{minipage}`
  \begin{minipage}[t]{.23\textwidth}

  \end{minipage}
  %\\ \hline
\end{tabular}

\vspace{1.0cm}
\noindent
\large{\textsc{\textbf{\textcolor{urcabrown}{\@title}}}}


% \vspace{-0.2cm}
\noindent
\begin{tabular}{@{}ll@{}}
 \begin{minipage}[t]{0.5\textwidth}
  \normalsize{\textbf{\@author}}
 \end{minipage}
 &
 \begin{minipage}[t]{0.5\textwidth}
  \normalsize{\texttt{\@email}}
 \end{minipage}
\end{tabular}


\small \normalfont

\vspace{0.8cm}

\scriptsize
\begin{tabular}{@{}p{0.33\textwidth}>{\columncolor{urcalightbrown!20}}p{0.66\textwidth}@{}}
% \begin{tabular}{@{}c@{}@{}c@{}}
  \begin{minipage}[t]{.23\textwidth}
    \noindent \textbf{\textcolor{urcabrown}{Métriques}}
    
    \vspace{0.2cm}
    \noindent
    {\scriptsize \textbf{Finalisé le :} \@date} \\
    {\scriptsize \textbf{Page(s) :}  \pageref{LastPage}} \\
    {\scriptsize \textbf{Références(s) :}  \@totref} \\
    {\scriptsize \textbf{Figure(s) :} \@totfig} \\
    {\scriptsize \textbf{Table(s) :} \@tottab} \\
    {\scriptsize \textbf{Théorème(s) :} \@tottheo}  \\
    

  \end{minipage}  
   % \end{minipage}%}
   &
   % \begin{minipage}[t]{0.66\textwidth}
      \noindent \textbf{\textcolor{urcabrown}{ Résumé :}} {\@resume}
      
      \vspace{0.2cm}
      \noindent
     % \fcolorbox{urcalightbrown!60}{urcalightbrown!20}{%
   % \begin{minipage}{0.34\textwidth}%{\dimexpr0.34\textwidth-2\fboxrule-2\fboxsep\relax}
      \textcolor{urcabrown}{\textbf{Mots-clés :}} % \\
      \@keywords
      
  \vspace{0.2cm}
   \noindent
   \textcolor{urcabrown}{\textbf{Matériel supplémentaire :}}
   
   \noindent \faGit :  {\@gitrepo} 
   
   \noindent \faDatabase :  {\@database} 
      
      
   % \end{minipage}
\end{tabular}

%  \global\let\thanks\relax
%  \global\let\maketitle\relax
%  \global\let\@maketitle\relax
%  \global\let\@thanks\@empty
%  \global\let\@author\@empty
%  \global\let\@date\@empty
%  \global\let\@title\@empty
%  \global\let\title\relax
%  \global\let\author\relax
%  \global\let\date\relax
%  \global\let\and\relax
}

