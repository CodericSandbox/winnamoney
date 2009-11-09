class Order < ActiveRecord::Base
  
  SUSCRIPTION = 189.00
  
  belongs_to  :user
  belongs_to  :cart
  has_many    :transactions, :class_name => "OrderTransaction"
  has_many    :payments
  
  validates_presence_of :account_number, :message => 'Debes proporcionar tu n&uacute;mero de cuenta',
                        :if => :deposit?
  validates_presence_of :account_type, :message => 'Debes proporcionar tu tipo de cuenta',
                        :if => :deposit?
  validates_presence_of :routing, :message => 'Debes proporcionar el routing del banco',
                        :if => :deposit? 
                             
  validate_on_create    :validate_card, :if => :credit_card?            
                        
  attr_accessor         :card_number, :card_verification
    
  def contact_me?
    contact_me
  end  
  
  def deposit?
    self.payment_method == "deposit"
  end
  
  def credit_card?
    self.payment_method == "credit_card"
  end
  
  def contact_later?
    self.payment_method == "contact_later"
  end
  
  def suscription?
    self.order_type == "suscription"
  end
  
  def product_purchase?
    self.order_type == "product_purchase"
  end
  
  def purchase!
    response = process_purchase
    transactions.create!(:action => "purchase", :amount => price_in_cents, :response => response)
    response.success?
  end

  def complete!
    self.status = 'complete'
    self.payments.create(:payment_method => 'credit_card', :amount => price_in_cents)
    self.cart.complete! if self.product_purchase?
    self.user.store.activate! if self.suscription?
    self.save
  end
  
  def declined!
    self.status = 'declined'
    self.save
  end
  
  def express_token=(token)
    self[:express_token] = token
    if new_record? && !token.blank?
      details = EXPRESS_GATEWAY.details_for(token)
      self.express_payer_id = details.payer_id
      self.first_name = details.params["first_name"]
      self.last_name = details.params["last_name"]
    end
  end
  
  def price_in_cents
    if self.cart.nil?
      (SUSCRIPTION * 100).round
    else
      (self.cart.total * 100).round
    end
  end
  
  protected
  
  def process_purchase
    if express_token.blank?
      STANDARD_GATEWAY.purchase(price_in_cents, credit_card, standard_purchase_options)
    else
      EXPRESS_GATEWAY.purchase(price_in_cents, express_purchase_options)
    end
  end
  
  def standard_purchase_options
    {
      :ip => ip_address
    }
  end
  
  def express_purchase_options
    {
      :ip => ip_address,
      :token => express_token,
      :payer_id => express_payer_id
    }
  end
  
  def validate_card
    logger.warn "TOKEN: #{express_token}"
    if express_token.blank? && !credit_card.valid?
      credit_card.errors.full_messages.each do |message|
        errors.add_to_base message
      end
    end
  end
  
  def credit_card
    @credit_card ||= ActiveMerchant::Billing::CreditCard.new(
      :type               => card_type,
      :number             => card_number,
      :verification_value => card_verification,
      :month              => card_expires_on.month,
      :year               => card_expires_on.year,
      :first_name         => first_name,
      :last_name          => last_name
    )
  end
  
end