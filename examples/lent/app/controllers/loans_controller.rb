# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The list of what is out and what came back, and the form to lend
# something or to change what was written.
class LoansController < ApplicationController
  before_action :set_loan, only: %i[edit update destroy return]

  # The list: what is out, longest first, then the last twenty things
  # that came back.
  def index
    @out = Loan.out
    @back = Loan.back.limit(20)
  end

  # The form to lend something, lent today unless you say otherwise.
  def new
    @loan = Loan.new(lent_on: Date.today)
  end

  # The form to change what was written about a loan.
  def edit; end

  # Saves a new loan and goes back to the list, or shows the form again
  # with each error beside its field.
  def create
    @loan = Loan.new(loan_params)
    if @loan.save
      redirect_to root_path
    else
      render :new, status: :unprocessable_content
    end
  end

  # Saves a change, as create saves a new loan.
  def update
    if @loan.update(loan_params)
      redirect_to root_path
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Marks a loan come back today.
  def return
    @loan.return!
    redirect_to root_path
  end

  # Forgets a loan.
  def destroy
    @loan.destroy!
    redirect_to root_path
  end

  private def set_loan
    @loan = Loan.find(params[:id])
  end

  private def loan_params
    params.expect(loan: %i[thing borrower lent_on note])
  end
end
